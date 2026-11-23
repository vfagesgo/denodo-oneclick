#!/usr/bin/env python3
"""
Assigns the Property Groups created by 2_import_property_groups.py to views,
web services and asset extensions (p.k.a. external elements), and sets their
property values - creating or updating them - in the Denodo Data Catalog /
Data Marketplace, using the public REST API (see dm-api-docs.json):

  Groups / properties:
    GET  /public/api/property-management/groups
    GET  /public/api/property-management/groups/{groupId}/properties
  Current state:
    GET  /public/api/property-management/groups/{groupId}/elements/{VIEWS|WEBSERVICES}?offset&limit
    GET  /public/api/property-management/groups/{groupId}/elements/external-elements
    GET  /public/api/property-management/groups/{groupId}/elements/views/{viewId}/properties
    GET  /public/api/property-management/groups/{groupId}/elements/webservices/{webServiceId}/properties
  Assign groups (existing groups of the element are kept):
    POST /public/api/property-management/{views|webservices|external-elements}/{id}/groups  [groupIds]
  Set values (batch, grouped by property + value):
    PUT  /public/api/property-management/elements/properties          (update)
    POST /public/api/property-management/assign-property-to-elements  (fallback: first assignment)
         body: [{customPropertyId, elementType, elementIds, visualValue}]
  Unassign a group from an element (only with --prune):
    DELETE .../groups/{groupId}/elements/{views|webservices}?elementIds=..
    DELETE .../groups/{groupId}/elements/external-elements          [ids]

Elements are resolved by name exactly like 3_assign_domains.py (shared code).

Assignment is additive: group assignments are merged with whatever the element
already has, and only values that differ are written. Two separate input files
(e.g. bank_demo then pharm_ai) can therefore be applied one after the other
without the second run undoing the first. With --prune, any property group an
element still has that is NOT listed for that element in the JSON is removed
(unassigning a group also clears that group's values on the element); pruning is
scoped to the elements present in the JSON, so it only overwrites their mapping.

Input JSON (default: 4_property_assignments.json next to this script) is a list
of entries applied IN ORDER - a later entry overrides values of an earlier one
for the same element (use this for exceptions, e.g. PII views):

  [
    { "comment": "free text, ignored",
      "views":       ["bank_demo.customers"],          # "database.name" or {"id"}
      "webservices": ["bank_demo.bank_demo_rest_ws"],
      "assets":      ["TrialPulse: 360 Patient Insights"],
      "groups": {
        "Data Product Details": {                       # group name
          "Status": "🟢 Active",                         # property name -> value
          "Domain": "Sales & Commercial > Account Management"
        },
        "Data Product Owners": {}                       # {} = assign group, keep defaults
      } }
  ]

Values are checked against the server definition (group/property names exist,
ENUMERATION values are allowed options, max 4000 chars) before any change.
Values already set to the same value are left alone.

Usage:
  python3 4_assign_property_groups.py [--file 4_property_assignments.json]
        [--base-url URL] [--user admin] [--password admin] [--server-id 1]
        [--prune] [--dry-run] [--debug]

Requires: pip install requests  (and 3_assign_domains.py in the same folder)
"""

import argparse
import importlib.util
import json
import os
import sys

import requests

HERE = os.path.dirname(os.path.abspath(__file__))

# Reuse the HTTP client and the name -> id resolution of step 3.
_spec = importlib.util.spec_from_file_location("assign_domains", os.path.join(HERE, "3_assign_domains.py"))
step3 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(step3)

PM = "/public/api/property-management"
VALUE_MAX = 4000

# JSON key -> (elementType for value APIs, path segment for group assignment,
#              path segment for "elements of a group", path for current values)
KINDS = {
    "views": ("VIEWS", "views", "VIEWS", "views"),
    "webservices": ("WEBSERVICES", "webservices", "WEBSERVICES", "webservices"),
    "assets": ("EXTERNAL_ELEMENTS", "external-elements", None, None),
}

_extract_items = step3._extract_items


def _enum_values(prop):
    out = []
    for v in prop.get("possibleValues") or []:
        if isinstance(v, dict):
            v = v.get("value", v.get("name", v.get("visualValue")))
        out.append(v)
    return out


def _value_of(item):
    for k in ("visualValue", "value", "propertyValue", "currentValue"):
        if k in item:
            v = item[k]
            return v.get("visualValue", v.get("value")) if isinstance(v, dict) else v
    return None


def _prop_id_of(item):
    for k in ("propertyId", "customPropertyId", "id"):
        if isinstance(item.get(k), int):
            return item[k]
    if isinstance(item.get("property"), dict):
        return item["property"].get("id")
    return None


# --------------------------------------------------------------------------- #
# Catalog state
# --------------------------------------------------------------------------- #
class Catalog:
    def __init__(self, client, debug=False):
        self.c = client
        self.debug = debug
        self.groups = {}       # name -> {"id", "props": {name: prop}}
        self.members = {}      # (kind, element_id) -> set(group_ids)
        self.values = {}       # (kind, element_id, group_id) -> {prop_id: value} | None (unknown)

    def load_groups(self):
        for g in _extract_items(self.c.call("GET", f"{PM}/groups")):
            props = _extract_items(self.c.call("GET", f"{PM}/groups/{g['id']}/properties"))
            self.groups[g.get("name")] = {"id": g["id"], "props": {p.get("name"): p for p in props}}
        return self.groups

    def load_members(self):
        """Which element already has which group (needed to keep existing groups)."""
        for gname, g in self.groups.items():
            gid = g["id"]
            for kind, (_, _, list_type, _) in KINDS.items():
                try:
                    if list_type:
                        items = self.c.paged("GET", f"{PM}/groups/{gid}/elements/{list_type}")
                    else:
                        items = _extract_items(self.c.call("GET", f"{PM}/groups/{gid}/elements/external-elements"))
                except RuntimeError as exc:
                    print(f"   (could not list {kind} of group '{gname}': {exc})")
                    continue
                if self.debug and items:
                    print(f"   [debug] group '{gname}' {kind} item: {json.dumps(items[0], default=str)[:400]}")
                for it in items:
                    eid = it.get("id", it.get("elementId"))
                    if eid is not None:
                        self.members.setdefault((kind, eid), set()).add(gid)

    def current_values(self, kind, eid, gid):
        key = (kind, eid, gid)
        if key not in self.values:
            seg = KINDS[kind][3]
            if seg is None or gid not in self.members.get((kind, eid), set()):
                self.values[key] = None if seg is None else {}
            else:
                try:
                    items = _extract_items(self.c.call("GET", f"{PM}/groups/{gid}/elements/{seg}/{eid}/properties"))
                    if self.debug and items:
                        print(f"   [debug] values item: {json.dumps(items[0], default=str)[:400]}")
                    vals = {_prop_id_of(i): _value_of(i) for i in items if _prop_id_of(i) is not None}
                    self.values[key] = vals
                except RuntimeError:
                    self.values[key] = None
        return self.values[key]


# --------------------------------------------------------------------------- #
# Plan
# --------------------------------------------------------------------------- #
def validate_shape(entries):
    errors = []
    for i, e in enumerate(entries):
        where = f"entry[{i}]" + (f" ({e.get('comment')})" if isinstance(e, dict) and e.get("comment") else "")
        if not isinstance(e, dict):
            errors.append(f"{where}: must be an object")
            continue
        unknown = set(e) - {"comment", "groups", *KINDS}
        if unknown:
            errors.append(f"{where}: unknown keys {sorted(unknown)}")
        if not any(e.get(k) for k in KINDS):
            errors.append(f"{where}: no views/webservices/assets listed")
        groups = e.get("groups")
        if not isinstance(groups, dict) or not groups:
            errors.append(f"{where}: 'groups' must be a non-empty object")
            continue
        for gname, props in groups.items():
            if not isinstance(props, dict):
                errors.append(f"{where}: group '{gname}' must map property names to values")
    return errors


def validate_against_catalog(entries, catalog):
    errors = []
    for i, e in enumerate(entries):
        where = f"entry[{i}]" + (f" ({e.get('comment')})" if e.get("comment") else "")
        for gname, props in e["groups"].items():
            g = catalog.groups.get(gname)
            if g is None:
                errors.append(f"{where}: property group '{gname}' not found (run 2_import_property_groups.py)")
                continue
            for pname, value in props.items():
                p = g["props"].get(pname)
                if p is None:
                    errors.append(f"{where}: property '{pname}' not found in group '{gname}'")
                    continue
                if not isinstance(value, str) or len(value) > VALUE_MAX:
                    errors.append(f"{where}: '{gname}.{pname}' must be a string of at most {VALUE_MAX} chars")
                elif p.get("type") == "ENUMERATION" and value not in _enum_values(p):
                    errors.append(f"{where}: '{gname}.{pname}' = '{value}' is not one of {_enum_values(p)}")
    return errors


def build_plan(entries, catalog, index, stats):
    """
    Returns desired state: {(kind, eid): {"label", "groups": {gid: {prop_id: value}}}}
    Later entries override earlier ones.
    """
    desired = {}
    for e in entries:
        for kind in KINDS:
            for ref in e.get(kind) or []:
                try:
                    eid, label = index.resolve(kind, ref)
                except LookupError as exc:
                    stats["not_found"] += 1
                    if exc.args and exc.args[0]:
                        print(f"   ! {kind}: {exc}")
                    continue
                d = desired.setdefault((kind, eid), {"label": f"{kind[:-1]} {label}", "groups": {}})
                for gname, props in e["groups"].items():
                    g = catalog.groups[gname]
                    vals = d["groups"].setdefault(g["id"], {})
                    for pname, value in props.items():
                        vals[g["props"][pname]["id"]] = value
    return desired


# --------------------------------------------------------------------------- #
# Apply
# --------------------------------------------------------------------------- #
def apply_groups(client, catalog, desired, stats):
    print("\n== Property groups ==")
    names = {g["id"]: n for n, g in catalog.groups.items()}
    for (kind, eid), d in desired.items():
        have = catalog.members.get((kind, eid), set())
        missing = set(d["groups"]) - have
        if not missing:
            stats["groups_unchanged"] += 1
            continue
        target = sorted(have | set(d["groups"]))  # keep groups already assigned
        try:
            client.write("POST", f"{PM}/{KINDS[kind][1]}/{eid}/groups", json=target)
            catalog.members[(kind, eid)] = set(target)
            stats["groups_assigned"] += len(missing)
            print(f"   + {d['label']}: {sorted(names[g] for g in missing)}")
        except RuntimeError as exc:
            stats["failed"] += 1
            print(f"   ! {d['label']}: FAILED - {exc}")


def apply_values(client, catalog, desired, stats):
    print("\n== Property values ==")
    prop_names = {p["id"]: f"{gn}.{pn}" for gn, g in catalog.groups.items() for pn, p in g["props"].items()}
    labels = {k: d["label"] for k, d in desired.items()}
    # (prop_id, kind, value, is_new) -> [eids]
    batches = {}
    for (kind, eid), d in desired.items():
        for gid, vals in d["groups"].items():
            current = catalog.current_values(kind, eid, gid)
            for pid, value in vals.items():
                if current is not None and current.get(pid) == value:
                    stats["values_unchanged"] += 1
                    continue
                is_new = current is not None and pid not in current
                batches.setdefault((pid, kind, value, is_new), []).append(eid)

    for (pid, kind, value, is_new), eids in sorted(batches.items(), key=lambda b: (prop_names[b[0][0]], b[0][1])):
        body = [{"customPropertyId": pid, "elementType": KINDS[kind][0],
                 "elementIds": sorted(eids), "visualValue": value}]
        shown = value if len(value) <= 60 else value[:57] + "..."
        who = ", ".join(labels[(kind, e)].split(" ", 1)[1] for e in sorted(eids))
        # Known-new values -> assign; existing or unknown -> update, then assign as fallback.
        first, second = (("POST", f"{PM}/assign-property-to-elements"), ("PUT", f"{PM}/elements/properties"))
        if not is_new:
            first, second = second, first
        try:
            try:
                client.write(*first, json=body)
            except RuntimeError:
                client.write(*second, json=body)
            stats["values_set"] += len(eids)
            print(f"   = {prop_names[pid]} = '{shown}' -> {who}")
        except RuntimeError as exc:
            stats["failed"] += 1
            print(f"   ! {prop_names[pid]} -> {who}: FAILED - {exc}")


def unassign_group(client, kind, gid, eid):
    """Remove one property group from one element (also clears its values)."""
    seg = KINDS[kind][1]  # views | webservices | external-elements
    path = f"{PM}/groups/{gid}/elements/{seg}"
    if kind == "assets":
        client.write("DELETE", path, json=[eid])            # external-elements: ids in body
    else:
        client.write("DELETE", path, params={"elementIds": [eid]})  # views/webservices: query


def apply_prune(client, catalog, desired, stats):
    """Remove property groups an element has that are not listed for it in the JSON.

    Scoped to the elements present in the input, so running one file does not
    touch elements managed by another file.
    """
    print("\n== Prune (remove property groups not in the input) ==")
    names = {g["id"]: n for n, g in catalog.groups.items()}
    for (kind, eid), d in desired.items():
        have = catalog.members.get((kind, eid), set())
        extra = have - set(d["groups"])
        for gid in sorted(extra):
            try:
                unassign_group(client, kind, gid, eid)
                catalog.members[(kind, eid)].discard(gid)
                stats["groups_removed"] += 1
                print(f"   - {d['label']}: {names.get(gid, gid)}")
            except RuntimeError as exc:
                stats["failed"] += 1
                print(f"   ! {d['label']}: could not unassign {names.get(gid, gid)} - {exc}")


def main():
    ap = argparse.ArgumentParser(description="Assign property groups and values to views, web services and assets.")
    ap.add_argument("--file", default=os.path.join(HERE, "4_property_assignments.json"))
    ap.add_argument("--base-url", default=os.environ.get("DENODO_DC_URL", "http://localhost/denodo-data-catalog"))
    ap.add_argument("--user", default=os.environ.get("DENODO_USER", "admin"))
    ap.add_argument("--password", default=os.environ.get("DENODO_PASSWORD", "admin"))
    ap.add_argument("--server-id", default=os.environ.get("DENODO_SERVER_ID", "1"))
    ap.add_argument("--prune", action="store_true",
                    help="also remove property groups an element has but that are not listed for it in the JSON")
    ap.add_argument("--dry-run", action="store_true", help="read only: show what would change")
    ap.add_argument("--debug", action="store_true", help="print raw samples of API answers")
    args = ap.parse_args()

    with open(args.file, encoding="utf-8") as f:
        entries = json.load(f)
    if isinstance(entries, dict):
        entries = [entries]
    errors = validate_shape(entries)
    if errors:
        print("Input validation failed:\n  " + "\n  ".join(errors))
        return 2

    client = step3.Client(args.base_url, args.user, args.password, args.server_id, args.dry_run)
    catalog = Catalog(client, args.debug)
    catalog.load_groups()
    print(f"Found {len(catalog.groups)} property groups on {client.base} (serverId={args.server_id}).")

    errors = validate_against_catalog(entries, catalog)
    if errors:
        print("Input does not match the catalog:\n  " + "\n  ".join(errors))
        return 2

    stats = dict.fromkeys(("groups_assigned", "groups_unchanged", "groups_removed",
                           "values_set", "values_unchanged", "not_found", "failed"), 0)
    index = step3.ElementIndex(client, debug=args.debug)
    print(f"\n== Resolving elements from {args.file}{' (dry run)' if args.dry_run else ''} ==")
    desired = build_plan(entries, catalog, index, stats)
    print(f"{len(desired)} element(s) to process.")

    catalog.load_members()
    apply_groups(client, catalog, desired, stats)
    apply_values(client, catalog, desired, stats)
    if args.prune:
        apply_prune(client, catalog, desired, stats)

    print("\n== Done ==  " + ", ".join(f"{k}={v}" for k, v in stats.items()))
    return 1 if stats["failed"] or stats["not_found"] else 0


if __name__ == "__main__":
    sys.exit(main())
