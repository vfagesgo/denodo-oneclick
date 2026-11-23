#!/usr/bin/env python3
"""
Imports (create or update) custom Property Groups and their Properties into the
Denodo Data Catalog / Data Marketplace using the public REST API
(`property-management`, see dm-api-docs.json):

  GET  /public/api/property-management/groups                      Get all property groups
  POST /public/api/property-management/groups                      Create group  (PropertyGroupInput)
  PUT  /public/api/property-management/groups                      Update group  (UpdatePropertyGroupInput, id in body)
  GET  /public/api/property-management/groups/{groupId}/properties Get properties of a group
  POST /public/api/property-management/groups/{groupId}/properties Add property (PropertyInput)
  PUT  /public/api/property-management/properties?updateAssignments=<bool>
                                                                   Update property (UpdatePropertyInput, id in body)
  POST /public/api/property-management/groups/{groupId}/check-property-compatible-to-update
                                                                   Pre-check before changing a property's type
  POST /public/api/property-management/groups/{groupId}/properties/sort
                                                                   Keep the JSON order of properties

Input JSON (default: 2_property_groups.json next to this script):

  [
    { "name": "...", "description": "...", "descriptionType": "TEXT|RICH_TEXT",
      "placeToShow": "SUMMARY_TAB|GENERAL_CUSTOM_PROPERTY_TAB|SPECIFIC_CUSTOM_PROPERTY_TAB",
      "aiUsageEnabled": true,
      "properties": [
        { "name": "...", "description": "...", "descriptionType": "TEXT|RICH_TEXT",
          "type": "TEXT|LONG_TEXT|RICH_TEXT|ENUMERATION",
          "interpolable": false, "defaultValue": "...",
          "possibleValues": ["..."] }               # ENUMERATION only
      ] }
  ]

Groups are matched by name; properties by name inside their group. Existing
items are updated only when a field differs; missing ones are created.
Enumeration values that disappear from `possibleValues` are sent in
`updateEnum.deleted`, with the property's defaultValue as replacement.

This script does NOT assign groups to views/web services/asset extensions.

Usage:
  python3 2_import_property_groups.py [--file 2_property_groups.json]
        [--base-url URL] [--user admin] [--password admin] [--server-id 1]
        [--update-assignments] [--no-sort] [--dry-run]

Requires: pip install requests
"""

import argparse
import json
import os
import sys

import requests

API = "/public/api/property-management"
GROUPS = f"{API}/groups"
PROPERTIES = f"{API}/properties"

DESCRIPTION_TYPES = {"TEXT", "RICH_TEXT"}
PLACES = {"SUMMARY_TAB", "GENERAL_CUSTOM_PROPERTY_TAB", "SPECIFIC_CUSTOM_PROPERTY_TAB"}
PROPERTY_TYPES = {"TEXT", "LONG_TEXT", "RICH_TEXT", "ENUMERATION"}
NAME_MAX, TEXT_MAX = 255, 4000  # schema constraints

GROUP_FIELDS = ("name", "description", "descriptionType", "placeToShow", "aiUsageEnabled")
PROPERTY_FIELDS = ("name", "description", "descriptionType", "type", "interpolable", "defaultValue")


# --------------------------------------------------------------------------- #
# API client
# --------------------------------------------------------------------------- #
class PropertyClient:
    def __init__(self, base_url, user, password, server_id, dry_run=False):
        self.base = base_url.rstrip("/")
        self.params = {"serverId": server_id} if server_id else {}
        self.dry_run = dry_run
        self.s = requests.Session()
        self.s.auth = (user, password)
        self.s.headers.update({"Accept": "application/json"})
        self._fake_id = 0

    def _call(self, method, path, params=None, **kw):
        url = self.base + path
        params = {**self.params, **(params or {})}
        resp = self.s.request(method, url, params=params, **kw)
        # Spring Security CSRF: a 403 may hand back a token; echo it and retry once.
        if resp.status_code == 403:
            token = resp.headers.get("X-XSRF-TOKEN") or self.s.cookies.get("XSRF-TOKEN")
            if token and self.s.headers.get("X-XSRF-TOKEN") != token:
                self.s.headers["X-XSRF-TOKEN"] = token
                resp = self.s.request(method, url, params=params, **kw)
        if not resp.ok:
            raise RuntimeError(f"{method} {path} -> {resp.status_code}: {resp.text[:500]}")
        try:
            return resp.json() if resp.text else None
        except ValueError:
            return None

    def _write(self, method, path, **kw):
        """Mutating call; in dry-run returns a fake object with a negative id."""
        if self.dry_run:
            self._fake_id -= 1
            return {"id": self._fake_id}
        return self._call(method, path, **kw)

    # -- groups ------------------------------------------------------------ #
    def groups(self):
        return {g.get("name"): g for g in _extract_items(self._call("GET", GROUPS))}

    def create_group(self, body):
        return _id_of(self._write("POST", GROUPS, json=body))

    def update_group(self, group_id, body):
        self._write("PUT", GROUPS, json={**body, "id": group_id})
        return group_id

    # -- properties -------------------------------------------------------- #
    def properties(self, group_id):
        if self.dry_run and group_id < 0:
            return {}
        items = _extract_items(self._call("GET", f"{GROUPS}/{group_id}/properties"))
        return {p.get("name"): p for p in items}

    def create_property(self, group_id, body):
        return _id_of(self._write("POST", f"{GROUPS}/{group_id}/properties", json=body))

    def check_type_change(self, group_id, prop_id, new_type):
        if self.dry_run:
            return None
        return self._call("POST", f"{GROUPS}/{group_id}/check-property-compatible-to-update",
                          json={"id": prop_id, "type": new_type})

    def update_property(self, prop_id, body, update_assignments):
        self._write("PUT", PROPERTIES, json={**body, "id": prop_id},
                    params={"updateAssignments": str(update_assignments).lower()})
        return prop_id

    def sort_properties(self, group_id, ids):
        self._write("POST", f"{GROUPS}/{group_id}/properties/sort", json=ids)


def _extract_items(payload):
    """Response schemas are undocumented: accept a list or a wrapped object."""
    if isinstance(payload, list):
        return [i for i in payload if isinstance(i, dict)]
    if isinstance(payload, dict):
        for key in ("content", "elements", "items", "data", "results",
                    "groups", "propertyGroups", "properties"):
            if isinstance(payload.get(key), list):
                return [i for i in payload[key] if isinstance(i, dict)]
    return []


def _id_of(payload):
    return payload.get("id") if isinstance(payload, dict) else None


def _enum_values(item):
    """possibleValues may come back as strings or objects ({value|name|...})."""
    out = []
    for v in item.get("possibleValues") or []:
        if isinstance(v, dict):
            v = v.get("value", v.get("name", v.get("visualValue")))
        out.append(v)
    return out


# --------------------------------------------------------------------------- #
# Payload builders + diff
# --------------------------------------------------------------------------- #
def group_body(cfg):
    return {
        "name": cfg["name"],
        "description": cfg.get("description", ""),
        "descriptionType": cfg.get("descriptionType", "TEXT"),
        "placeToShow": cfg.get("placeToShow", "GENERAL_CUSTOM_PROPERTY_TAB"),
        "aiUsageEnabled": bool(cfg.get("aiUsageEnabled", False)),
    }


def property_body(cfg):
    body = {
        "name": cfg["name"],
        "description": cfg.get("description", ""),
        "descriptionType": cfg.get("descriptionType", "TEXT"),
        "type": cfg.get("type", "TEXT"),
        "interpolable": bool(cfg.get("interpolable", False)),
        "defaultValue": cfg.get("defaultValue", ""),
    }
    if body["type"] == "ENUMERATION":
        body["possibleValues"] = list(cfg.get("possibleValues") or [])
    return body


def changed_fields(existing, body, fields):
    diff = [f for f in fields if f in existing and existing.get(f) != body.get(f)]
    if body.get("type") == "ENUMERATION" and _enum_values(existing) != body.get("possibleValues"):
        diff.append("possibleValues")
    return diff


# --------------------------------------------------------------------------- #
# Validation
# --------------------------------------------------------------------------- #
def validate(groups):
    errors = []
    seen_groups = set()

    def check_text(where, cfg, key, limit, required=True):
        v = cfg.get(key)
        if v is None:
            if required:
                errors.append(f"{where}: '{key}' is required")
        elif not isinstance(v, str) or len(v) > limit:
            errors.append(f"{where}: '{key}' must be a string of at most {limit} chars")

    for gi, g in enumerate(groups):
        where = f"group[{gi}]"
        if not isinstance(g, dict) or not isinstance(g.get("name"), str) or not g["name"]:
            errors.append(f"{where}: 'name' is required")
            continue
        where = f"group '{g['name']}'"
        if g["name"] in seen_groups:
            errors.append(f"{where}: duplicate group name")
        seen_groups.add(g["name"])
        check_text(where, g, "name", NAME_MAX)
        check_text(where, g, "description", TEXT_MAX, required=False)
        if g.get("descriptionType", "TEXT") not in DESCRIPTION_TYPES:
            errors.append(f"{where}: descriptionType must be one of {sorted(DESCRIPTION_TYPES)}")
        if g.get("placeToShow", "GENERAL_CUSTOM_PROPERTY_TAB") not in PLACES:
            errors.append(f"{where}: placeToShow must be one of {sorted(PLACES)}")

        seen_props = set()
        for pi, p in enumerate(g.get("properties") or []):
            pwhere = f"{where} property[{pi}]"
            if not isinstance(p, dict) or not isinstance(p.get("name"), str) or not p["name"]:
                errors.append(f"{pwhere}: 'name' is required")
                continue
            pwhere = f"{where} property '{p['name']}'"
            if p["name"] in seen_props:
                errors.append(f"{pwhere}: duplicate property name in group")
            seen_props.add(p["name"])
            check_text(pwhere, p, "name", NAME_MAX)
            check_text(pwhere, p, "description", TEXT_MAX, required=False)
            check_text(pwhere, p, "defaultValue", TEXT_MAX, required=False)
            if p.get("descriptionType", "TEXT") not in DESCRIPTION_TYPES:
                errors.append(f"{pwhere}: descriptionType must be one of {sorted(DESCRIPTION_TYPES)}")
            ptype = p.get("type", "TEXT")
            if ptype not in PROPERTY_TYPES:
                errors.append(f"{pwhere}: type must be one of {sorted(PROPERTY_TYPES)}")
            if ptype == "ENUMERATION":
                values = p.get("possibleValues") or []
                if not values:
                    errors.append(f"{pwhere}: ENUMERATION needs 'possibleValues'")
                elif len(set(values)) != len(values):
                    errors.append(f"{pwhere}: duplicate entries in 'possibleValues'")
                default = p.get("defaultValue")
                if default and default not in values:
                    errors.append(f"{pwhere}: defaultValue '{default}' is not in possibleValues")
    return errors


# --------------------------------------------------------------------------- #
# Import
# --------------------------------------------------------------------------- #
def import_property(client, group_id, cfg, existing_props, args, stats):
    name = cfg["name"]
    body = property_body(cfg)
    existing = existing_props.get(name)

    if existing is None:
        prop_id = client.create_property(group_id, body)
        stats["properties_created"] += 1
        print(f"   - {name}: created (id={prop_id})")
        return prop_id

    prop_id = existing.get("id")
    diff = changed_fields(existing, body, PROPERTY_FIELDS)
    if not diff:
        stats["properties_unchanged"] += 1
        print(f"   - {name}: unchanged (id={prop_id})")
        return prop_id

    if "type" in diff:
        client.check_type_change(group_id, prop_id, body["type"])

    if body["type"] == "ENUMERATION" and existing.get("type") == "ENUMERATION":
        removed = [v for v in _enum_values(existing) if v not in body["possibleValues"]]
        body["updateEnum"] = {
            "edited": [],
            "deleted": [{"current": v, "newValue": body["defaultValue"]} for v in removed],
        }

    client.update_property(prop_id, body, args.update_assignments)
    stats["properties_updated"] += 1
    print(f"   - {name}: updated (id={prop_id}) fields={diff}")
    return prop_id


def import_group(client, cfg, existing_groups, args, stats):
    name = cfg["name"]
    body = group_body(cfg)
    existing = existing_groups.get(name)

    if existing is None:
        group_id = client.create_group(body)
        if group_id is None and not client.dry_run:  # no id in response -> re-read
            group_id = _id_of(client.groups().get(name))
        stats["groups_created"] += 1
        print(f"{name}: created (id={group_id})")
    else:
        group_id = existing.get("id")
        diff = changed_fields(existing, body, GROUP_FIELDS)
        if diff:
            client.update_group(group_id, body)
            stats["groups_updated"] += 1
            print(f"{name}: updated (id={group_id}) fields={diff}")
        else:
            stats["groups_unchanged"] += 1
            print(f"{name}: unchanged (id={group_id})")

    props = cfg.get("properties") or []
    if group_id is None:
        print(f"   ! no id for group '{name}', skipping {len(props)} property(ies)")
        stats["skipped"] += len(props)
        return

    existing_props = client.properties(group_id)
    created_before = stats["properties_created"]
    ordered_ids = []
    for prop_cfg in props:
        try:
            pid = import_property(client, group_id, prop_cfg, existing_props, args, stats)
        except (RuntimeError, requests.RequestException) as exc:
            stats["failed"] += 1
            print(f"   - {prop_cfg['name']}: FAILED - {exc}")
            continue
        if pid is None and not client.dry_run:  # no id in response -> re-read
            existing_props = client.properties(group_id)
            pid = _id_of(existing_props.get(prop_cfg["name"]))
        ordered_ids.append(pid)

    added = stats["properties_created"] > created_before
    if args.sort and added and not client.dry_run and None not in ordered_ids:
        # New properties were appended: restore JSON order, then any extra
        # properties already in the group.
        others = [p.get("id") for n, p in client.properties(group_id).items()
                  if p.get("id") not in ordered_ids]
        try:
            client.sort_properties(group_id, ordered_ids + others)
        except (RuntimeError, requests.RequestException) as exc:
            print(f"   ! could not sort properties: {exc}")


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description="Import property groups/properties into Denodo Data Catalog.")
    ap.add_argument("--file", default=os.path.join(here, "2_property_groups.json"))
    ap.add_argument("--base-url", default=os.environ.get("DENODO_DC_URL", "http://localhost/denodo-data-catalog"))
    ap.add_argument("--user", default=os.environ.get("DENODO_USER", "admin"))
    ap.add_argument("--password", default=os.environ.get("DENODO_PASSWORD", "admin"))
    ap.add_argument("--server-id", default=os.environ.get("DENODO_SERVER_ID", "1"))
    ap.add_argument("--update-assignments", action="store_true",
                    help="propagate property changes to elements already using them (updateAssignments=true)")
    ap.add_argument("--no-sort", dest="sort", action="store_false",
                    help="do not reorder properties to match the JSON order")
    ap.add_argument("--dry-run", action="store_true", help="read only: show what would be created/updated")
    args = ap.parse_args()

    with open(args.file, encoding="utf-8") as f:
        groups = json.load(f)
    if isinstance(groups, dict):
        groups = [groups]

    errors = validate(groups)
    if errors:
        print("Input validation failed:\n  " + "\n  ".join(errors))
        return 2

    client = PropertyClient(args.base_url, args.user, args.password, args.server_id, args.dry_run)
    existing_groups = client.groups()
    print(f"Found {len(existing_groups)} existing property groups on {client.base} (serverId={args.server_id}).")

    stats = dict.fromkeys(("groups_created", "groups_updated", "groups_unchanged",
                           "properties_created", "properties_updated", "properties_unchanged",
                           "failed", "skipped"), 0)
    print(f"\n== Importing {args.file}{' (dry run)' if args.dry_run else ''} ==")
    for cfg in groups:
        try:
            import_group(client, cfg, existing_groups, args, stats)
        except (RuntimeError, requests.RequestException) as exc:
            stats["failed"] += 1
            stats["skipped"] += len(cfg.get("properties") or [])
            print(f"{cfg['name']}: FAILED - {exc}")

    print("\n== Done ==  " + ", ".join(f"{k}={v}" for k, v in stats.items()))
    return 1 if stats["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
