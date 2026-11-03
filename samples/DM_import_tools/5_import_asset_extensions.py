#!/usr/bin/env python3
"""
Imports (create or update) the asset-extension building blocks of the Denodo
Data Catalog / Data Marketplace, using the public REST API (see dm-api-docs.json):

  1. Asset extension (p.k.a. external element) types
       GET  /public/api/external-elements-types
       POST /public/api/external-elements-types          CreateExternalElementTypeRequest
       PUT  /public/api/external-elements-types/{id}     UpdateExternalElementTypeRequest
  2. External provider types (name + visual name + icon)
       GET  /public/api/external-providers-types
       POST /public/api/external-providers-types         multipart: request (json) + icon
       PUT  /public/api/external-providers-types/{id}    multipart: request (json) + icon
  3. Asset extension (p.k.a. external tool) servers - CUSTOM type, mapping a
     provider type to a VDP interface view (databaseName.viewName)
       GET  /public/api/external-tool-servers[/{id}]
       POST /public/api/external-tool-servers            CustomServerConfigurationRequest
       PUT  /public/api/external-tool-servers/{id}       CustomServerConfigurationRequest
  Optional synchronization (--sync / --sync-vdp):
       POST /public/api/element-management/all/synchronize   (VDP views -> catalog)
       POST /public/api/external-tool-servers/synchronize    (servers in the JSON)

Input JSON (default: 5_asset_extensions.json next to this script):

  { "elementTypes":  [ {name, visualName, description, iconKey, iconColorCode, reversedIconColorCode} ],
    "providerTypes": [ {name, visualName, icon: "icons/x.svg"} ],          # icon path relative to the JSON
    "toolServers":   [ {name, description, databaseName, viewName,
                        providerType: "QLIK"  |  providerTypeId: 103,     # name from providerTypes/catalog, or id
                        sync: false} ] }                                  # optional: exclude from --sync

Everything is matched by name (element/provider types: technical name; tool
servers: server name). Existing items are updated when a field differs - the
provider icon included, when the API returns it - otherwise created. Use
--force to update every existing item regardless.

To only synchronize, without importing anything, use --no-import together with
--sync and/or --sync-vdp. In that mode --sync synchronizes every tool server
already present in the catalog (no input file is read):

  python3 5_import_asset_extensions.py --no-import --sync
  python3 5_import_asset_extensions.py --no-import --sync-vdp --sync

Usage:
  python3 5_import_asset_extensions.py [--file 5_asset_extensions.json]
        [--only element-types|provider-types|tool-servers] [--force]
        [--sync] [--sync-vdp] [--no-import] [--dry-run] [--debug]
        [--base-url URL] [--user admin] [--password admin] [--server-id 1]

Requires: pip install requests  (and 3_assign_domains.py in the same folder)
"""

import argparse
import base64
import importlib.util
import json
import mimetypes
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# Reuse the HTTP client (Basic auth, serverId, CSRF retry, dry-run) of step 3.
_spec = importlib.util.spec_from_file_location("assign_domains", os.path.join(HERE, "3_assign_domains.py"))
step3 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(step3)
_extract_items = step3._extract_items

API = "/public/api"
ELEMENT_TYPES = f"{API}/external-elements-types"
PROVIDER_TYPES = f"{API}/external-providers-types"
TOOL_SERVERS = f"{API}/external-tool-servers"

ELEMENT_TYPE_FIELDS = ("visualName", "description", "iconKey", "iconColorCode", "reversedIconColorCode")
LIMITS = {"name": 80, "description": 4000, "visualName": 255, "iconKey": 100,
          "iconColorCode": 20, "reversedIconColorCode": 20}
mimetypes.add_type("image/svg+xml", ".svg")


def _get(item, *keys):
    for k in keys:
        if item.get(k) not in (None, ""):
            return item[k]
    return None


def _short_error(exc, limit=400):
    """VDP errors are long execution traces: keep the failing node and its message."""
    text = str(exc)
    try:
        text = json.loads(text.split(": ", 1)[1]).get("message", text)
    except (IndexError, ValueError, AttributeError):
        pass
    lines = [l.strip() for l in text.splitlines() if l.strip()]
    # Leaf node of the trace = the line carrying an error type other than "[ERROR]"
    leaves = [l for l in lines if "Received exception" in l or "_ERROR]" in l]
    return " | ".join(leaves or lines[:1])[:limit]


def _diff(existing, wanted, fields):
    """Fields present in the API answer whose value differs from the JSON."""
    return [f for f in fields if f in existing and existing.get(f) != wanted.get(f)]


class Importer:
    def __init__(self, client, base_dir, force=False, debug=False):
        self.c = client
        self.base_dir = base_dir
        self.force = force
        self.debug = debug
        self.provider_ids = {}   # name (lower) -> id, filled by provider step or catalog
        self.server_ids = []     # (name, id) of the servers from the JSON (for --sync)
        self.fake_id = 0
        self.stats = dict.fromkeys(("created", "updated", "unchanged", "failed", "synced", "sync_failed"), 0)

    def _fake(self):
        self.fake_id -= 1
        return self.fake_id

    def _debug(self, label, items):
        if self.debug and items:
            print(f"   [debug] {label}: {json.dumps(items[0], default=str)[:500]}")

    def _report(self, kind, name, status, ident=None, diff=None, exc=None):
        if status == "failed":
            self.stats["failed"] += 1
            print(f"   ! {kind} {name}: FAILED - {exc}")
            return
        self.stats[status] += 1
        extra = f" fields={diff}" if diff else ""
        print(f"   {kind} {name}: {status} (id={ident}){extra}")

    # ------------------------------------------------------------------ #
    # 1. Element types
    # ------------------------------------------------------------------ #
    def element_types(self, wanted):
        print("\n== Asset extension (external element) types ==")
        items = _extract_items(self.c.call("GET", ELEMENT_TYPES))
        self._debug("element type", items)
        existing = {str(_get(i, "externalElementTypeName", "name")).upper(): i for i in items}
        for et in wanted:
            name = et["name"]
            body = {k: et.get(k, "") for k in ELEMENT_TYPE_FIELDS}
            cur = existing.get(name.upper())
            try:
                if cur is None:
                    resp = self.c.write("POST", ELEMENT_TYPES, json={"name": name, **body})
                    ident = _get(resp or {}, "externalElementTypeId", "id") or (self._fake() if self.c.dry_run else None)
                    self._report("element type", name, "created", ident)
                    continue
                ident = _get(cur, "externalElementTypeId", "id")
                diff = _diff(cur, body, ELEMENT_TYPE_FIELDS)
                if not diff and not self.force:
                    self._report("element type", name, "unchanged", ident)
                    continue
                self.c.write("PUT", f"{ELEMENT_TYPES}/{ident}", json=body)
                self._report("element type", name, "updated", ident, diff or ["--force"])
            except RuntimeError as exc:
                self._report("element type", name, "failed", exc=exc)

    # ------------------------------------------------------------------ #
    # 2. Provider types
    # ------------------------------------------------------------------ #
    def _load_providers(self):
        items = _extract_items(self.c.call("GET", PROVIDER_TYPES))
        self._debug("provider type", items)
        for i in items:
            ident = _get(i, "externalProviderTypeId", "id")
            for key in (_get(i, "name"), _get(i, "visualName")):
                if key:
                    self.provider_ids.setdefault(str(key).lower(), ident)
        return items

    def provider_types(self, wanted):
        print("\n== External provider types ==")
        items = self._load_providers()
        existing = {str(_get(i, "name")).upper(): i for i in items}
        for pt in wanted:
            name = pt["name"]
            request = {"name": name, "visualName": pt["visualName"]}
            icon_path = os.path.join(self.base_dir, pt["icon"]) if pt.get("icon") else None
            icon = open(icon_path, "rb").read() if icon_path else None
            cur = existing.get(name.upper())
            files = {"request": (None, json.dumps(request), "application/json")}
            if icon is not None:
                mime = mimetypes.guess_type(icon_path)[0] or "application/octet-stream"
                files["icon"] = (os.path.basename(icon_path), icon, mime)
            try:
                if cur is None:
                    resp = self.c.write("POST", PROVIDER_TYPES, files=files)
                    ident = _get(resp or {}, "externalProviderTypeId", "id")
                    if ident is None and not self.c.dry_run:
                        self._load_providers()
                        ident = self.provider_ids.get(name.lower())
                    ident = ident if ident is not None else self._fake()
                    self.provider_ids[name.lower()] = ident
                    self._report("provider type", name, "created", ident)
                    continue
                ident = _get(cur, "externalProviderTypeId", "id")
                self.provider_ids[name.lower()] = ident
                diff = _diff(cur, request, ("visualName",))
                if icon is not None and cur.get("iconImage"):
                    try:
                        if base64.b64decode(cur["iconImage"]) != icon:
                            diff.append("icon")
                    except (ValueError, TypeError):
                        diff.append("icon")
                if not diff and not self.force:
                    self._report("provider type", name, "unchanged", ident)
                    continue
                self.c.write("PUT", f"{PROVIDER_TYPES}/{ident}", files=files)
                self._report("provider type", name, "updated", ident, diff or ["--force"])
            except RuntimeError as exc:
                self._report("provider type", name, "failed", exc=exc)

    # ------------------------------------------------------------------ #
    # 3. Tool servers
    # ------------------------------------------------------------------ #
    def _server_details(self, item):
        """List entries may be partial: complete them with GET /{id}."""
        ident = _get(item, "id", "externalToolServerId")
        if ident is None or all(k in item for k in ("databaseName", "viewName")):
            return item
        try:
            details = self.c.call("GET", f"{TOOL_SERVERS}/{ident}") or {}
            self._debug("tool server details", [details])
            return {**item, **details} if isinstance(details, dict) else item
        except RuntimeError:
            return item

    @staticmethod
    def _server_provider_id(item):
        pid = _get(item, "externalProviderTypeId", "providerTypeId")
        if pid is None:
            for k in ("externalProviderType", "providerType"):
                if isinstance(item.get(k), dict):
                    pid = _get(item[k], "externalProviderTypeId", "id")
        return pid

    def tool_servers(self, wanted):
        print("\n== Asset extension (external tool) servers ==")
        if not self.provider_ids:
            self._load_providers()
        items = _extract_items(self.c.call("GET", TOOL_SERVERS))
        self._debug("tool server", items)
        existing = {str(_get(i, "name")).lower(): i for i in items}
        for ts in wanted:
            name = ts["name"]
            pid = ts.get("providerTypeId")
            if pid is None:
                pid = self.provider_ids.get(str(ts.get("providerType", "")).lower())
            if pid is None:
                self._report("tool server", name, "failed",
                             exc=f"provider type '{ts.get('providerType')}' not found")
                continue
            body = {"type": "CUSTOM", "name": name, "description": ts.get("description", ""),
                    "externalProviderTypeId": pid, "databaseName": ts["databaseName"],
                    "viewName": ts["viewName"]}
            cur = existing.get(name.lower())
            try:
                if cur is None:
                    resp = self.c.write("POST", TOOL_SERVERS, json=body)
                    ident = _get(resp or {}, "id", "externalToolServerId")
                    if ident is None and not self.c.dry_run:
                        fresh = _extract_items(self.c.call("GET", TOOL_SERVERS))
                        ident = next((_get(i, "id", "externalToolServerId") for i in fresh
                                      if str(_get(i, "name")).lower() == name.lower()), None)
                    ident = ident if ident is not None else self._fake()
                    self.server_ids.append((name, ident, ts.get("sync", True)))
                    self._report("tool server", name, "created", ident)
                    continue
                cur = self._server_details(cur)
                ident = _get(cur, "id", "externalToolServerId")
                self.server_ids.append((name, ident, ts.get("sync", True)))
                diff = _diff(cur, body, ("description", "databaseName", "viewName"))
                cur_pid = self._server_provider_id(cur)
                if cur_pid is not None and cur_pid != pid:
                    diff.append("externalProviderTypeId")
                if not diff and not self.force:
                    self._report("tool server", name, "unchanged", ident)
                    continue
                self.c.write("PUT", f"{TOOL_SERVERS}/{ident}", json=body)
                self._report("tool server", name, "updated", ident, diff or ["--force"])
            except RuntimeError as exc:
                self._report("tool server", name, "failed", exc=exc)

    # ------------------------------------------------------------------ #
    # Synchronization
    # ------------------------------------------------------------------ #
    def sync_vdp(self):
        print("\n== Synchronizing VDP elements ==")
        body = {"proceedWithConflicts": "SERVER_WITH_LOCAL_CHANGES", "matchedElements": []}
        try:
            self.c.write("POST", f"{API}/element-management/all/synchronize", json=body)
            print("   done")
        except RuntimeError as exc:
            self.stats["failed"] += 1
            print(f"   ! FAILED - {exc}")

    def sync_servers(self, all_servers=False):
        print("\n== Synchronizing asset extension servers ==")
        if all_servers:
            # Sync-only mode (--no-import): synchronize every tool server
            # currently in the catalog, independent of any input file.
            try:
                items = _extract_items(self.c.call("GET", TOOL_SERVERS))
            except RuntimeError as exc:
                self.stats["sync_failed"] += 1
                print(f"   ! could not list tool servers - {exc}")
                return
            pending = [(it.get("name"), it.get("id")) for it in items if it.get("id") is not None]
            if not pending:
                print("   (no tool servers found in the catalog)")
                return
        else:
            if not self.server_ids:
                print("   (no tool servers processed - run without --only, or with --only tool-servers)")
                return
            pending = []  # [(name, id)] in JSON order
            for name, ident, enabled in self.server_ids:
                if not enabled:
                    print(f"   {name} (id={ident}): skipped (\"sync\": false)")
                elif ident is not None and (ident >= 0 or self.c.dry_run):
                    pending.append((name, ident))
            if not pending:
                return

        def sync(ids):
            self.c.write("POST", f"{TOOL_SERVERS}/synchronize", json={"externalToolServerIds": ids})

        # 1. Everything in one batch (assets of different servers reference each
        #    other, the batch lets the catalog resolve those associations).
        try:
            sync([i for _, i in pending])
            self.stats["synced"] += len(pending)
            print(f"   all {len(pending)} servers synchronized in one batch")
            return
        except RuntimeError as exc:
            print(f"   batch failed ({_short_error(exc, 200)})")
            print("   -> retrying server by server, in dependency rounds")

        # 2. Rounds of individual syncs: a server whose dependencies are now
        #    loaded succeeds; the others are retried in the next round.
        last_error, done, rnd = {}, [], 0
        while pending:
            rnd += 1
            progress = []
            for name, ident in pending:
                try:
                    sync([ident])
                    progress.append((name, ident))
                    print(f"   round {rnd}: {name} (id={ident}) synchronized")
                except RuntimeError as exc:
                    last_error[ident] = _short_error(exc)
            pending = [p for p in pending if p not in progress]
            done += progress
            if not progress:
                break

        # 3. Leftovers together (mutual dependencies). If a broken server spoils
        #    the batch, retry without each candidate in turn to isolate it.
        while len(pending) > 1:
            group = None
            for skip in [None] + list(pending):
                candidate = [p for p in pending if p != skip]
                if len(candidate) < 2 and skip is not None:
                    continue
                try:
                    sync([i for _, i in candidate])
                    group = candidate
                    break
                except RuntimeError as exc:
                    if skip is None:
                        print(f"   leftovers batch failed ({_short_error(exc, 200)})")
            if not group:
                break
            print(f"   synchronized together: {[n for n, _ in group]}")
            done += group
            pending = [p for p in pending if p not in group]

        # 4. Re-sync what succeeded so associations to servers loaded later are created.
        if len(done) > 1 and rnd > 1:
            try:
                sync([i for _, i in done])
                print("   final pass: associations refreshed")
            except RuntimeError as exc:
                print(f"   ! final pass failed ({_short_error(exc, 200)})")

        self.stats["synced"] += len(done)
        for name, ident in pending:
            self.stats["sync_failed"] += 1
            print(f"   ! {name} (id={ident}): FAILED - {last_error.get(ident, 'see batch error')}")


# --------------------------------------------------------------------------- #
# Validation
# --------------------------------------------------------------------------- #
def validate(cfg, base_dir):
    errors = []

    def check(where, item, required):
        for k in required:
            if not isinstance(item.get(k), str) or not item[k]:
                errors.append(f"{where}: '{k}' is required")
        for k, limit in LIMITS.items():
            if isinstance(item.get(k), str) and len(item[k]) > limit:
                errors.append(f"{where}: '{k}' longer than {limit} chars")

    def unique(section):
        names = [str(i.get("name", "")).lower() for i in cfg.get(section, [])]
        dupes = sorted({n for n in names if names.count(n) > 1})
        if dupes:
            errors.append(f"{section}: duplicate names {dupes}")

    for i, et in enumerate(cfg.get("elementTypes", [])):
        check(f"elementTypes[{i}]", et, ("name", "visualName", "iconKey", "iconColorCode", "reversedIconColorCode"))
    provider_names = set()
    for i, pt in enumerate(cfg.get("providerTypes", [])):
        check(f"providerTypes[{i}]", pt, ("name", "visualName"))
        provider_names.add(str(pt.get("name", "")).lower())
        if pt.get("icon") and not os.path.isfile(os.path.join(base_dir, pt["icon"])):
            errors.append(f"providerTypes[{i}]: icon file '{pt['icon']}' not found")
    for i, ts in enumerate(cfg.get("toolServers", [])):
        check(f"toolServers[{i}]", ts, ("name", "databaseName", "viewName"))
        if ts.get("providerTypeId") is None and not ts.get("providerType"):
            errors.append(f"toolServers[{i}]: 'providerType' (name) or 'providerTypeId' is required")
    for section in ("elementTypes", "providerTypes", "toolServers"):
        unique(section)
    unknown = set(cfg) - {"elementTypes", "providerTypes", "toolServers"}
    if unknown:
        errors.append(f"unknown top-level keys {sorted(unknown)}")
    return errors


def main():
    ap = argparse.ArgumentParser(description="Create/update asset extension types, provider types and servers.")
    ap.add_argument("--file", default=os.path.join(HERE, "5_asset_extensions.json"))
    ap.add_argument("--only", choices=("element-types", "provider-types", "tool-servers"))
    ap.add_argument("--force", action="store_true", help="update existing items even if no difference is detected")
    ap.add_argument("--sync", action="store_true", help="synchronize the tool servers of the JSON afterwards")
    ap.add_argument("--sync-vdp", action="store_true", help="synchronize VDP elements first (before --sync)")
    ap.add_argument("--no-import", action="store_true",
                    help="skip the JSON import and only synchronize; with --sync this syncs every "
                         "tool server already in the catalog. Needs --sync and/or --sync-vdp.")
    ap.add_argument("--dry-run", action="store_true", help="read only: show what would change")
    ap.add_argument("--debug", action="store_true", help="print raw samples of API answers")
    ap.add_argument("--strict", action="store_true",
                    help="exit non-zero if any item failed to import or any server failed to "
                         "synchronize. By default the run is best-effort and exits 0 so a calling "
                         "install script is not aborted by an expected sync error.")
    ap.add_argument("--base-url", default=os.environ.get("DENODO_DC_URL", "http://localhost/denodo-data-catalog"))
    ap.add_argument("--user", default=os.environ.get("DENODO_USER", "admin"))
    ap.add_argument("--password", default=os.environ.get("DENODO_PASSWORD", "admin"))
    ap.add_argument("--server-id", default=os.environ.get("DENODO_SERVER_ID", "1"))
    args = ap.parse_args()

    if args.no_import:
        if not (args.sync or args.sync_vdp):
            print("--no-import does nothing on its own; add --sync and/or --sync-vdp.")
            return 2
        base_dir = HERE
        cfg = {}
    else:
        base_dir = os.path.dirname(os.path.abspath(args.file))
        with open(args.file, encoding="utf-8") as f:
            cfg = json.load(f)
        errors = validate(cfg, base_dir)
        if errors:
            print("Input validation failed:\n  " + "\n  ".join(errors))
            return 2

    client = step3.Client(args.base_url, args.user, args.password, args.server_id, args.dry_run)
    imp = Importer(client, base_dir, force=args.force, debug=args.debug)
    print(f"Target: {client.base} (serverId={args.server_id}){' - DRY RUN' if args.dry_run else ''}")

    if not args.no_import:
        if args.only in (None, "element-types"):
            imp.element_types(cfg.get("elementTypes", []))
        if args.only in (None, "provider-types"):
            imp.provider_types(cfg.get("providerTypes", []))
        if args.only in (None, "tool-servers"):
            imp.tool_servers(cfg.get("toolServers", []))
    if args.sync_vdp:
        imp.sync_vdp()
    if args.sync:
        imp.sync_servers(all_servers=args.no_import)

    print("\n== Done ==  " + ", ".join(f"{k}={v}" for k, v in imp.stats.items()))

    # Some tool servers legitimately cannot be synchronized (e.g. a server whose
    # backing VDP metadata view errors, or one whose 'id' the API reports as
    # null). Those are already caught per-server and counted in sync_failed, and
    # the same goes for individual import failures. Treat them as warnings and
    # exit 0 by default, so a calling install script running under `set -e` is
    # not aborted by an expected, non-fatal condition. Pass --strict to make any
    # such failure exit non-zero (e.g. in CI).
    problems = imp.stats["failed"] + imp.stats["sync_failed"]
    if problems:
        print(f"WARNING: {imp.stats['failed']} import failure(s) and "
              f"{imp.stats['sync_failed']} sync failure(s) - see messages above.")
        if args.strict:
            print("Exiting non-zero because --strict was given.")
            return 1
        print("Continuing (non-fatal); re-run with --strict to treat these as errors.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
