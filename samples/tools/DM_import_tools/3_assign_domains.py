#!/usr/bin/env python3
"""
Assigns views, web services and asset extensions (p.k.a. external elements)
to Domain categories in the Denodo Data Catalog / Data Marketplace, using the
public REST API (see dm-api-docs.json):

  Resolve domains:
    GET  /public/api/category-management/categories
  Resolve elements (name -> id), paged:
    POST /public/api/element-management/metadata/{VIEWS|WEBSERVICES|EXTERNAL_ELEMENTS}
         ?offset=&limit=   body: ElementFilterInput
  Current content of a domain:
    GET  /public/api/category-management/categories/{id}/views?offset=&limit=
    GET  /public/api/category-management/categories/{id}/webservices?offset=&limit=
    GET  /public/api/category-management/categories/{id}/external-elements
  Assign (additive):
    POST /public/api/category-management/categories/{id}/views              [ids]
    POST /public/api/category-management/categories/{id}/webservices        [ids]
    POST /public/api/category-management/categories/{id}/external-elements  [ids]
  Unassign (only with --prune):
    DELETE .../categories/{id}/views?elementIds=..        (same for webservices)
    DELETE .../categories/{id}/external-elements          [ids]

Input JSON (default: 3_domain_assignments.json next to this script):

  [
    { "domain": ["Pharma / Life Sciences", "Clinical Trials"],   # path from the root
      "views":       ["pharm_ai.clinical_trials", {"id": 42}],     # "database.view" or {"id"}
      "webservices": ["pharm_ai.ws_patients"],                     # "database.webservice" or {"id"}
      "assets":      ["TrialPulse: 360 Patient Insights",          # asset extension name
                      {"name": "Trial Site"}, {"id": 7}] }         # or {"name"} / {"id"}
  ]

The domain is a path (list of names) because the same name may exist under
different parents. Run 1_import_domains.py first. Items already in the domain
are left alone; only missing ones are added. With --prune, items in the domain
that are not listed in the JSON are removed (only for domains in the JSON).

Usage:
  python3 3_assign_domains.py [--file 3_domain_assignments.json] [--base-url URL]
        [--user admin] [--password admin] [--server-id 1] [--prune] [--dry-run]

Requires: pip install requests
"""

import argparse
import difflib
import json
import os
import sys

import requests

CATEGORIES = "/public/api/category-management/categories"
ELEMENTS = "/public/api/element-management/metadata"
# element-management/metadata/EXTERNAL_ELEMENTS returns web services, not asset
# extensions, so assets are listed through the dedicated search endpoints.
ASSET_SEARCH = "/public/api/search/external-elements/metadata"
ASSET_ENGINE_SEARCH = "/public/api/search/engine/external-elements/metadata"
ASSET_BASIC_SEARCH = "/public/api/permission-management/external-elements/search"
ASSET_SERVERS = "/public/api/external-tool-servers"
PAGE = 500

# JSON key -> (element-management type, category sub-resource, paged GET?)
KINDS = {
    "views": ("VIEWS", "views", True),
    "webservices": ("WEBSERVICES", "webservices", True),
    "assets": ("EXTERNAL_ELEMENTS", "external-elements", False),
}


# --------------------------------------------------------------------------- #
# API client
# --------------------------------------------------------------------------- #
class Client:
    def __init__(self, base_url, user, password, server_id, dry_run=False):
        self.base = base_url.rstrip("/")
        self.params = {"serverId": server_id} if server_id else {}
        self.dry_run = dry_run
        self.s = requests.Session()
        self.s.auth = (user, password)
        self.s.headers.update({"Accept": "application/json"})

    def call(self, method, path, params=None, **kw):
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

    def write(self, method, path, **kw):
        return None if self.dry_run else self.call(method, path, **kw)

    def paged(self, method, path, **kw):
        """Fetch every page of an offset/limit endpoint."""
        out, offset, seen = [], 0, set()
        while True:
            items = _extract_items(self.call(method, path, params={"offset": offset, "limit": PAGE}, **kw))
            page_ids = {i.get("id") for i in items}
            if page_ids and page_ids <= seen:  # server ignored offset -> stop
                return out
            seen |= page_ids
            out.extend(items)
            if len(items) < PAGE:
                return out
            offset += PAGE

    ASSET_FILTERS = {"categoryIds": [], "tagIds": [], "externalToolServerIds": [],
                     "externalElementTypeIds": []}

    def _asset_search_body(self, text, offset=0, exact=False):
        body = {**self.ASSET_FILTERS, "text": text, "withEndorsements": False,
                "withWarnings": False, "withDeprecations": False,
                "offset": offset, "limit": PAGE}
        if text:
            body["whereToSearchList"] = ["ELEMENT_NAME"]
        if exact:
            body["searchType"] = "EXACT_MATCH"
        return body

    def list_assets(self, attempts_log):
        """
        All asset extensions (p.k.a. external elements). The search endpoints
        are text searches, so several strategies are tried until one returns
        something. Each attempt's raw answer is kept for diagnostics.
        """
        strategies = [
            ("search text=''", ASSET_SEARCH, lambda off: self._asset_search_body("", off), True),
            ("search text='*'", ASSET_SEARCH, lambda off: self._asset_search_body("*", off), True),
            ("engine search text='*'", ASSET_ENGINE_SEARCH, lambda off: self._asset_search_body("*", off), True),
            ("basic search", ASSET_BASIC_SEARCH, lambda off: dict(self.ASSET_FILTERS), False),
        ]
        for label, path, body_for, paged in strategies:
            out, offset, seen = [], 0, set()
            try:
                while True:
                    payload = self.call("POST", path, json=body_for(offset))
                    if offset == 0:
                        attempts_log.append((label, json.dumps(payload, default=str)[:400]))
                    items = _extract_items(payload)
                    page_ids = {i.get("id") for i in items}
                    if not paged or not items or (page_ids and page_ids <= seen) or len(items) < PAGE:
                        out.extend(i for i in items if i.get("id") not in seen)
                        break
                    seen |= page_ids
                    out.extend(items)
                    offset += PAGE
            except RuntimeError as exc:
                attempts_log.append((label, f"ERROR {exc}"[:400]))
                continue
            if out:
                attempts_log.append((label, f"-> {len(out)} assets"))
                return out
        return []

    def search_asset(self, name):
        """Targeted lookup of one asset by name (used when the full list is empty)."""
        for exact in (True, False):
            try:
                payload = self.call("POST", ASSET_SEARCH, json=self._asset_search_body(name, exact=exact))
            except RuntimeError:
                continue
            hits = [i for i in _extract_items(payload)
                    if (_element_name(i) or "").lower() == name.lower()]
            if hits:
                return hits
        return []

    def asset_servers(self):
        try:
            return _extract_items(self.call("GET", ASSET_SERVERS))
        except RuntimeError as exc:
            return [{"error": str(exc)[:200]}]


def _extract_items(payload):
    """Response schemas are undocumented: accept a list or a wrapped/paged object."""
    if isinstance(payload, list):
        return [i for i in payload if isinstance(i, dict)]
    if isinstance(payload, dict):
        for key in ("content", "elements", "items", "data", "results",
                    "views", "webservices", "externalElements"):
            if isinstance(payload.get(key), list):
                return [i for i in payload[key] if isinstance(i, dict)]
    return []


def _text(v):
    if isinstance(v, dict):  # e.g. "database": {"databaseId": 4, "databaseName": "bank_demo"}
        v = v.get("name") or v.get("databaseName")
    return v if isinstance(v, str) and v else None


def _first(item, *keys):
    for k in keys:
        v = _text(item.get(k))
        if v:
            return v
    return None


NAME_KEYS = ("name", "elementName", "viewName", "webserviceName", "vdpName", "localName")


def _element_name(item):
    return _first(item, *NAME_KEYS)


def _element_database(item):
    """Database name: known keys first, then any key that mentions database/db."""
    db = _first(item, "databaseName", "database", "vdpDatabaseName", "dbName", "database_name")
    if db:
        return db
    for k, v in item.items():
        kl = k.lower()
        if ("database" in kl or kl.startswith("db")) and not kl.endswith(("id", "ids")):
            if _text(v):
                return _text(v)
    return None


# --------------------------------------------------------------------------- #
# Domain resolution (path -> id)
# --------------------------------------------------------------------------- #
def load_domain_paths(client):
    items = _flatten(_extract_items(client.call("GET", CATEGORIES)))
    by_id = {i.get("id"): i for i in items}

    def path_of(item, guard=0):
        pid = _parent_of(item)
        if pid is None or pid not in by_id or guard > 50:
            return (item.get("name"),)
        return path_of(by_id[pid], guard + 1) + (item.get("name"),)

    return {path_of(i): i.get("id") for i in items}


def _flatten(items, parent_id=None):
    out = []
    for item in items:
        if parent_id is not None and _parent_of(item) is None:
            item = {**item, "parentId": parent_id}
        out.append(item)
        for key in ("children", "subcategories"):
            if isinstance(item.get(key), list):
                out.extend(_flatten([c for c in item[key] if isinstance(c, dict)], item.get("id")))
    return out


def _parent_of(item):
    pid = item.get("parentId")
    if pid is None and isinstance(item.get("parent"), dict):
        pid = item["parent"].get("id")
    return pid or None


# --------------------------------------------------------------------------- #
# Element resolution (name -> id)
# --------------------------------------------------------------------------- #
class ElementIndex:
    """Lazily loads all elements of a kind and indexes them by name."""

    def __init__(self, client, debug=False):
        self.client = client
        self.debug = debug
        self.cache = {}
        self.samples = {}
        self.explained = set()
        self.asset_attempts = []

    @staticmethod
    def _add(index, it):
        name = _element_name(it)
        db = _element_database(it)
        keys = {name, f"{db}.{name}" if db and name else None}
        # Some APIs return a fully-qualified name already ("db.view").
        if name and "." in name:
            keys.add(name.split(".", 1)[1])
        for key in keys - {None}:
            bucket = index.setdefault(key.lower(), [])
            if all(b.get("id") != it.get("id") for b in bucket):
                bucket.append(it)

    def _load(self, kind):
        if kind not in self.cache:
            if kind == "assets":
                items = self.client.list_assets(self.asset_attempts)
                if self.debug:
                    for label, raw in self.asset_attempts:
                        print(f"   [debug] assets {label}: {raw}")
            else:
                body = {"nameFilter": "", "descriptionFilter": ""}
                items = self.client.paged("POST", f"{ELEMENTS}/{KINDS[kind][0]}", json=body)
            index = {}
            for it in items:
                self._add(index, it)
            self.cache[kind] = index
            self.samples[kind] = items[:2]
            print(f"Loaded {len(items)} {kind} from the catalog.")
            if self.debug and items:
                print(f"   [debug] first {kind} item: {json.dumps(items[0], default=str)[:800]}")
        return self.cache[kind]

    def explain(self, kind, name):
        """Print what the API returned, once per kind, plus close matches."""
        index = self.cache.get(kind, {})
        close = difflib.get_close_matches(name.lower(), index.keys(), n=3, cutoff=0.6)
        if close:
            print(f"     close matches: {close}")
        if kind not in self.explained:
            self.explained.add(kind)
            sample = self.samples.get(kind) or []
            if sample:
                print(f"     [diag] {kind} item keys: {sorted(sample[0].keys())}")
                print(f"     [diag] sample: {json.dumps(sample[0], default=str)[:600]}")
            else:
                print(f"     [diag] the API returned no {kind}")
            if kind == "assets":
                for label, raw in self.asset_attempts:
                    print(f"     [diag] {label}: {raw}")
                servers = self.client.asset_servers()
                names = [s.get("name") or s for s in servers]
                print(f"     [diag] asset extension servers ({len(servers)}): {names}")
                print("     [diag] make sure these servers are synchronized "
                      "(Administration > Asset extension servers > Synchronize)")

    def resolve(self, kind, ref):
        """Return (id, label) or raise LookupError."""
        if isinstance(ref, dict) and ref.get("id") is not None:
            return ref["id"], f"id={ref['id']}"
        name = ref.get("name") if isinstance(ref, dict) else ref
        if not isinstance(name, str) or not name:
            raise LookupError(f"invalid reference {ref!r}")
        index = self._load(kind)
        matches = index.get(name.lower(), [])
        if not matches and kind == "assets":
            # The listing may be empty/incomplete (text search): look it up by name.
            for hit in self.client.search_asset(name):
                self._add(index, hit)
            matches = index.get(name.lower(), [])
        ids = {m.get("id") for m in matches}
        if not ids:
            print(f"   ! {kind}: '{name}' not found")
            self.explain(kind, name)
            raise LookupError(None)
        if len(ids) > 1:
            raise LookupError(f"'{name}' is ambiguous (ids {sorted(ids)}); "
                              f"use 'database.name' or {{\"id\": ...}}")
        return ids.pop(), name


# --------------------------------------------------------------------------- #
# Assignment
# --------------------------------------------------------------------------- #
def current_ids(client, category_id, kind):
    _, sub, paged = KINDS[kind]
    path = f"{CATEGORIES}/{category_id}/{sub}"
    items = client.paged("GET", path) if paged else _extract_items(client.call("GET", path))
    return {i.get("id") for i in items if i.get("id") is not None}


def assign(client, category_id, kind, ids):
    _, sub, _ = KINDS[kind]
    result = client.write("POST", f"{CATEGORIES}/{category_id}/{sub}", json=sorted(ids))
    # views/webservices: "Returns the identifier for the ... that could not be assigned"
    return [i for i in result if isinstance(i, int)] if isinstance(result, list) else []


def unassign(client, category_id, kind, ids):
    _, sub, _ = KINDS[kind]
    path = f"{CATEGORIES}/{category_id}/{sub}"
    if kind == "assets":
        client.write("DELETE", path, json=sorted(ids))
    else:
        client.write("DELETE", path, params={"elementIds": sorted(ids)})


def validate(entries):
    errors, seen = [], set()
    for i, e in enumerate(entries):
        where = f"entry[{i}]"
        dom = e.get("domain") if isinstance(e, dict) else None
        if not (isinstance(dom, list) and dom and all(isinstance(x, str) and x for x in dom)):
            errors.append(f"{where}: 'domain' must be a non-empty list of names (path from the root)")
            continue
        if tuple(dom) in seen:
            errors.append(f"{where}: domain {dom} listed twice - merge the entries")
        seen.add(tuple(dom))
        for kind in KINDS:
            if not isinstance(e.get(kind, []), list):
                errors.append(f"{where}: '{kind}' must be a list")
        unknown = set(e) - {"domain", *KINDS}
        if unknown:
            errors.append(f"{where}: unknown keys {sorted(unknown)} (expected domain, {', '.join(KINDS)})")
    return errors


def process_entry(client, index, domains, entry, args, stats):
    path = tuple(entry["domain"])
    label = " > ".join(path)
    category_id = domains.get(path)
    if category_id is None:
        stats["failed"] += 1
        print(f"\n{label}: FAILED - domain not found (run 1_import_domains.py first)")
        return
    print(f"\n{label} (id={category_id})")

    for kind in KINDS:
        refs = entry.get(kind) or []
        if not refs and not args.prune:
            continue
        wanted, unresolved = {}, 0
        for ref in refs:
            try:
                eid, name = index.resolve(kind, ref)
                wanted[eid] = name
            except LookupError as exc:
                unresolved += 1
                stats["not_found"] += 1
                if exc.args and exc.args[0]:
                    print(f"   ! {kind}: {exc}")

        try:
            present = current_ids(client, category_id, kind)
            to_add = set(wanted) - present
            to_remove = present - set(wanted) if args.prune else set()
            if to_remove and unresolved:
                # Never prune on an incomplete list: an unresolved ref may be one to keep.
                print(f"   ! {kind}: prune skipped ({unresolved} unresolved reference(s))")
                to_remove = set()

            for eid in sorted(set(wanted) & present):
                stats["unchanged"] += 1
                print(f"   = {kind}: {wanted[eid]} (already assigned)")
            if to_add:
                rejected = set(assign(client, category_id, kind, to_add))
                for eid in sorted(to_add):
                    if eid in rejected:
                        stats["failed"] += 1
                        print(f"   ! {kind}: {wanted[eid]} could not be assigned")
                    else:
                        stats["assigned"] += 1
                        print(f"   + {kind}: {wanted[eid]}")
            if to_remove:
                unassign(client, category_id, kind, to_remove)
                stats["removed"] += len(to_remove)
                print(f"   - {kind}: removed ids {sorted(to_remove)}")
        except (RuntimeError, requests.RequestException) as exc:
            stats["failed"] += 1
            print(f"   ! {kind}: FAILED - {exc}")


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description="Assign views, web services and asset extensions to domains.")
    ap.add_argument("--file", default=os.path.join(here, "3_domain_assignments.json"))
    ap.add_argument("--base-url", default=os.environ.get("DENODO_DC_URL", "http://localhost/denodo-data-catalog"))
    ap.add_argument("--user", default=os.environ.get("DENODO_USER", "admin"))
    ap.add_argument("--password", default=os.environ.get("DENODO_PASSWORD", "admin"))
    ap.add_argument("--server-id", default=os.environ.get("DENODO_SERVER_ID", "1"))
    ap.add_argument("--prune", action="store_true",
                    help="also remove items assigned to a listed domain but missing from the JSON")
    ap.add_argument("--dry-run", action="store_true", help="read only: show what would change")
    ap.add_argument("--debug", action="store_true", help="print a raw sample of each element list")
    args = ap.parse_args()

    with open(args.file, encoding="utf-8") as f:
        entries = json.load(f)
    if isinstance(entries, dict):
        entries = [entries]

    errors = validate(entries)
    if errors:
        print("Input validation failed:\n  " + "\n  ".join(errors))
        return 2

    client = Client(args.base_url, args.user, args.password, args.server_id, args.dry_run)
    domains = load_domain_paths(client)
    print(f"Found {len(domains)} domains on {client.base} (serverId={args.server_id}).")

    index = ElementIndex(client, debug=args.debug)
    stats = dict.fromkeys(("assigned", "unchanged", "removed", "not_found", "failed"), 0)
    print(f"\n== Assigning from {args.file}{' (dry run)' if args.dry_run else ''} ==")
    for entry in entries:
        process_entry(client, index, domains, entry, args, stats)

    print("\n== Done ==  " + ", ".join(f"{k}={v}" for k, v in stats.items()))
    return 1 if stats["failed"] or stats["not_found"] else 0


if __name__ == "__main__":
    sys.exit(main())
