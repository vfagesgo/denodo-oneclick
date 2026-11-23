#!/usr/bin/env python3
"""
Imports (create or update) a recursive Domain category tree into the Denodo
Data Catalog / Data Marketplace using the public REST API
(`category-management`, see dm-api-docs.json):

  GET  /public/api/category-management/categories               Find all categories
  POST /public/api/category-management/categories               Add a new category   (CategoryInput)
  PUT  /public/api/category-management/categories/{categoryId}  Update a category    (CategoryInput)

  CategoryInput = { name (1..80, required), description (0..4000, required),
                    descriptionType (TEXT|RICH_TEXT, required), parentId (int64) }

Every call carries the optional `serverId` query parameter. Authentication is
HTTP Basic, as declared by the API's security schemes.

Input JSON (default: 1_domains.json next to this script) is a list of nodes:

  [
    { "name": "Operations",
      "description": "<p>...</p>",          # HTML -> RICH_TEXT
      "subdomains": [                        # optional, any depth
        { "name": "Manufacturing", "description": "...", "subdomains": [ ... ] }
      ] }
  ]

A category is identified by (name, parentId). Existing -> updated (only if
its description differs), missing -> created. Parents are processed before
their children so each child gets the real parent id. A failure on one node
is reported and its sub-tree skipped; the rest of the import continues.

Usage:
  python3 1_import_domains.py [--file 1_domains.json] [--base-url URL]
                              [--user admin] [--password admin] [--server-id 1]
                              [--dry-run]

Requires: pip install requests
"""

import argparse
import json
import os
import sys

import requests

CATEGORIES = "/public/api/category-management/categories"
DESCRIPTION_TYPE = "RICH_TEXT"
NAME_MAX, DESCRIPTION_MAX = 80, 4000  # CategoryInput constraints


# --------------------------------------------------------------------------- #
# API client
# --------------------------------------------------------------------------- #
class CategoryClient:
    def __init__(self, base_url, user, password, server_id, dry_run=False):
        self.base = base_url.rstrip("/")
        self.params = {"serverId": server_id} if server_id else {}
        self.dry_run = dry_run
        self.s = requests.Session()
        self.s.auth = (user, password)
        self.s.headers.update({"Accept": "application/json"})
        self.index = {}  # (parentId, name) -> category dict
        self._fake_id = 0

    def _call(self, method, path, **kw):
        url = self.base + path
        resp = self.s.request(method, url, params=self.params, **kw)
        # Spring Security CSRF: a 403 may hand back a token; echo it and retry once.
        if resp.status_code == 403:
            token = resp.headers.get("X-XSRF-TOKEN") or self.s.cookies.get("XSRF-TOKEN")
            if token and self.s.headers.get("X-XSRF-TOKEN") != token:
                self.s.headers["X-XSRF-TOKEN"] = token
                resp = self.s.request(method, url, params=self.params, **kw)
        if not resp.ok:
            raise RuntimeError(f"{method} {path} -> {resp.status_code}: {resp.text[:500]}")
        try:
            return resp.json() if resp.text else None
        except ValueError:
            return None

    # -- read -------------------------------------------------------------- #
    def refresh(self):
        payload = self._call("GET", CATEGORIES)
        self.index = {}
        for item in _flatten(_extract_items(payload)):
            self.index[(_parent_of(item), item.get("name"))] = item
        return len(self.index)

    def find(self, name, parent_id):
        return self.index.get((parent_id, name))

    # -- write ------------------------------------------------------------- #
    @staticmethod
    def _input(name, description, parent_id):
        body = {"name": name, "description": description,
                "descriptionType": DESCRIPTION_TYPE}
        if parent_id is not None:
            body["parentId"] = parent_id
        return body

    def create(self, name, description, parent_id):
        body = self._input(name, description, parent_id)
        if self.dry_run:
            self._fake_id -= 1
            cid = self._fake_id
        else:
            created = self._call("POST", CATEGORIES, json=body)
            cid = created.get("id") if isinstance(created, dict) else None
            if cid is None:  # response has no documented schema -> re-read
                self.refresh()
                cid = (self.find(name, parent_id) or {}).get("id")
        self.index[(parent_id, name)] = {**body, "id": cid}
        return cid

    def update(self, existing, name, description, parent_id):
        cid = existing["id"]
        body = self._input(name, description, parent_id)
        if not self.dry_run:
            self._call("PUT", f"{CATEGORIES}/{cid}", json=body)
        self.index[(parent_id, name)] = {**existing, **body}
        return cid


def _extract_items(payload):
    """Response schema is undocumented: accept a list or a paged/wrapped object."""
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict):
        for key in ("content", "elements", "items", "data", "results", "categories"):
            if isinstance(payload.get(key), list):
                return payload[key]
    return []


def _flatten(items, parent_id=None):
    """Tolerate a tree-shaped answer (children/subcategories) by flattening it."""
    out = []
    for item in items:
        if not isinstance(item, dict):
            continue
        if parent_id is not None and _parent_of(item) is None:
            item = {**item, "parentId": parent_id}
        out.append(item)
        for key in ("children", "subcategories"):
            if isinstance(item.get(key), list):
                out.extend(_flatten(item[key], item.get("id")))
    return out


def _parent_of(item):
    pid = item.get("parentId")
    if pid is None and isinstance(item.get("parent"), dict):
        pid = item["parent"].get("id")
    return pid or None


# --------------------------------------------------------------------------- #
# Validation + recursive import
# --------------------------------------------------------------------------- #
def validate(nodes, path=""):
    errors = []
    for i, node in enumerate(nodes):
        where = f"{path}[{i}]"
        name = node.get("name") if isinstance(node, dict) else None
        if not isinstance(name, str) or not 1 <= len(name) <= NAME_MAX:
            errors.append(f"{where}: 'name' must be a string of 1..{NAME_MAX} chars")
            continue
        where = f"{path}/{name}"
        if len(node.get("description") or "") > DESCRIPTION_MAX:
            errors.append(f"{where}: 'description' longer than {DESCRIPTION_MAX} chars")
        subs = node.get("subdomains") or []
        if not isinstance(subs, list):
            errors.append(f"{where}: 'subdomains' must be a list")
            continue
        siblings = [s.get("name") for s in subs if isinstance(s, dict)]
        dupes = {n for n in siblings if siblings.count(n) > 1}
        if dupes:
            errors.append(f"{where}: duplicate subdomain names {sorted(dupes)}")
        errors.extend(validate(subs, where))
    return errors


def import_node(client, node, parent_id, depth, stats):
    name = node["name"]
    description = node.get("description") or ""
    prefix = "  " * depth + ("- " if depth else "")
    try:
        existing = client.find(name, parent_id)
        if existing is None:
            cid = client.create(name, description, parent_id)
            stats["created"] += 1
            status = "created"
        elif (existing.get("description") or "") == description:
            cid = existing.get("id")
            stats["unchanged"] += 1
            status = "unchanged"
        else:
            cid = client.update(existing, name, description, parent_id)
            stats["updated"] += 1
            status = "updated"
        print(f"{prefix}{name}: {status} (id={cid})")
    except (RuntimeError, requests.RequestException) as exc:
        stats["failed"] += 1
        print(f"{prefix}{name}: FAILED - {exc}")
        cid = None

    children = node.get("subdomains") or []
    if children and cid is None:
        print(f"{'  ' * (depth + 1)}! no id for '{name}', skipping {len(children)} subdomain(s)")
        stats["skipped"] += len(children)
        return
    for child in children:
        import_node(client, child, cid, depth + 1, stats)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description="Import a recursive domain/category tree into Denodo Data Catalog.")
    ap.add_argument("--file", default=os.path.join(here, "1_domains.json"))
    ap.add_argument("--base-url", default=os.environ.get("DENODO_DC_URL", "http://localhost/denodo-data-catalog"))
    ap.add_argument("--user", default=os.environ.get("DENODO_USER", "admin"))
    ap.add_argument("--password", default=os.environ.get("DENODO_PASSWORD", "admin"))
    ap.add_argument("--server-id", default=os.environ.get("DENODO_SERVER_ID", "1"))
    ap.add_argument("--dry-run", action="store_true", help="read only: show what would be created/updated")
    args = ap.parse_args()

    with open(args.file, encoding="utf-8") as f:
        tree = json.load(f)
    if isinstance(tree, dict):
        tree = [tree]

    errors = validate(tree)
    if errors:
        print("Input validation failed:\n  " + "\n  ".join(errors))
        return 2

    client = CategoryClient(args.base_url, args.user, args.password, args.server_id, args.dry_run)
    print(f"Found {client.refresh()} existing categories on {client.base} (serverId={args.server_id}).")

    stats = {"created": 0, "updated": 0, "unchanged": 0, "failed": 0, "skipped": 0}
    print(f"\n== Importing {args.file}{' (dry run)' if args.dry_run else ''} ==")
    for node in tree:
        import_node(client, node, None, 0, stats)

    print("\n== Done ==  " + ", ".join(f"{k}={v}" for k, v in stats.items()))
    return 1 if stats["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
