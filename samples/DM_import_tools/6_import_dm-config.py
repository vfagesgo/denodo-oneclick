#!/usr/bin/env python3
"""
Applies the Denodo Data Marketplace admin configuration (LLM, Vector DB,
Denodo Assistant) described in _6_dm-config.json, using the public REST API
(see dm-api-docs.json):

  POST /public/api/configuration/llm-configuration                       multipart: llmConfiguration (LlmDualConfigurationRequest)
  POST /public/api/configuration/vectordb-integration/api-configuration  multipart: vectorDbConfiguration (VectorDbConfigurationRequest)
  POST /public/api/configuration/vectordb-integration/vdp-server         VectorDbConfigureVdpServerRequest (one call per server)
  POST /public/api/configuration/ai-integration/assisted-query           AssistedQueryConfigurationRequest
  POST /public/api/configuration/personalization/denodo-assistant/chatbot ChatbotConfigurationRequest (chatbot + agent skills)
  GET  /public/api/configuration/configuration-details                   current configuration (saved as backup)

Each top-level section of the JSON is sent as-is (keys starting with '_' are
stripped). A missing section is skipped. Strings like "${OPENAI_API_KEY}" are
replaced by the matching environment variable when it is set, so secrets need
not be stored in the JSON.

Rollback: before applying, the current configuration returned by
configuration-details is saved to _6_dm-config.backup-<timestamp>.json.

Every call carries the optional `serverId` query parameter. Authentication is
HTTP Basic, as declared by the API's security schemes.

Usage:
  python3 6_import_dm-config.py [--file _6_dm-config.json] [--base-url URL]
                                [--user admin] [--password admin] [--server-id 1]
                                [--only llm,vectordb,servers,assisted-query,chatbot]
                                [--no-backup] [--dry-run]

Requires: pip install requests
"""

import argparse
import json
import os
import re
import sys
import time

import requests

CONFIG_DETAILS = "/public/api/configuration/configuration-details"
LLM = "/public/api/configuration/llm-configuration"
VECTOR_DB = "/public/api/configuration/vectordb-integration/api-configuration"
VDP_SERVER = "/public/api/configuration/vectordb-integration/vdp-server"
ASSISTED_QUERY = "/public/api/configuration/ai-integration/assisted-query"
CHATBOT = "/public/api/configuration/personalization/denodo-assistant/chatbot"

# step name -> (JSON section, endpoint, multipart part name or None for JSON body)
STEPS = [
    ("llm", "llmConfiguration", LLM, "llmConfiguration"),
    ("vectordb", "vectorDbConfiguration", VECTOR_DB, "vectorDbConfiguration"),
    ("servers", "vectorDbServers", VDP_SERVER, None),
    ("assisted-query", "assistedQuery", ASSISTED_QUERY, None),
    ("chatbot", "chatbot", CHATBOT, None),
]

ENV_REF = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}")


# --------------------------------------------------------------------------- #
# API client
# --------------------------------------------------------------------------- #
class ConfigClient:
    def __init__(self, base_url, user, password, server_id, dry_run=False):
        self.base = base_url.rstrip("/")
        self.params = {"serverId": server_id} if server_id else {}
        self.dry_run = dry_run
        self.s = requests.Session()
        self.s.auth = (user, password)
        self.s.headers.update({"Accept": "application/json"})

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
            return resp.text

    def get_details(self):
        return self._call("GET", CONFIG_DETAILS)

    def post_json(self, path, body):
        if self.dry_run:
            return None
        return self._call("POST", path, json=body)

    def post_multipart(self, path, part, body):
        if self.dry_run:
            return None
        files = {part: (None, json.dumps(body), "application/json")}
        return self._call("POST", path, files=files)


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
def clean(value, missing):
    """Strip '_' keys and resolve ${VAR} references (recursively)."""
    if isinstance(value, dict):
        return {k: clean(v, missing) for k, v in value.items() if not k.startswith("_")}
    if isinstance(value, list):
        return [clean(v, missing) for v in value]
    if isinstance(value, str):
        def sub(m):
            var = m.group(1)
            if var in os.environ:
                return os.environ[var]
            missing.add(var)
            return m.group(0)
        return ENV_REF.sub(sub, value)
    return value


def mask(value):
    """Hide secrets when printing a payload."""
    if isinstance(value, dict):
        return {k: ("***" if re.search(r"password|apikey|secret", k, re.I) and v else mask(v))
                for k, v in value.items()}
    if isinstance(value, list):
        return [mask(v) for v in value]
    return value


def validate(config):
    errors = []
    if not isinstance(config, dict):
        return ["root must be a JSON object"]
    for _, section, _, _ in STEPS:
        if section not in config:
            continue
        expected = list if section == "vectorDbServers" else dict
        if not isinstance(config[section], expected):
            errors.append(f"'{section}' must be a {expected.__name__}")
    for i, srv in enumerate(config.get("vectorDbServers") or []):
        for key in ("serverId", "username", "password", "dataUsageSampleSize"):
            if not isinstance(srv, dict) or key not in srv:
                errors.append(f"vectorDbServers[{i}]: missing '{key}'")
    return errors


def backup(client, folder):
    details = client.get_details()
    path = os.path.join(folder, f"_6_dm-config.backup-{time.strftime('%Y%m%d-%H%M%S')}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(details, f, indent=2)
    return path


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
def main():
    here = os.path.dirname(os.path.abspath(__file__))
    step_names = [s[0] for s in STEPS]
    ap = argparse.ArgumentParser(description="Apply Denodo Data Marketplace LLM / Vector DB / Assistant configuration.")
    ap.add_argument("--file", default=os.path.join(here, "_6_dm-config.json"))
    ap.add_argument("--base-url", default=os.environ.get("DENODO_DC_URL", "http://localhost/denodo-data-catalog"))
    ap.add_argument("--user", default=os.environ.get("DENODO_USER", "admin"))
    ap.add_argument("--password", default=os.environ.get("DENODO_PASSWORD", "admin"))
    ap.add_argument("--server-id", default=os.environ.get("DENODO_SERVER_ID", "1"))
    ap.add_argument("--only", help=f"comma-separated subset of: {','.join(step_names)}")
    ap.add_argument("--no-backup", action="store_true", help="do not save the current configuration first")
    ap.add_argument("--dry-run", action="store_true", help="print the payloads, send nothing")
    args = ap.parse_args()

    selected = step_names
    if args.only:
        selected = [s.strip() for s in args.only.split(",") if s.strip()]
        unknown = set(selected) - set(step_names)
        if unknown:
            print(f"Unknown step(s) in --only: {sorted(unknown)}. Valid: {step_names}")
            return 2

    with open(args.file, encoding="utf-8") as f:
        raw = json.load(f)
    errors = validate(raw)
    if errors:
        print("Input validation failed:\n  " + "\n  ".join(errors))
        return 2
    missing = set()
    config = clean(raw, missing)
    if missing:
        print(f"Warning: environment variable(s) not set, left as-is: {sorted(missing)}")

    client = ConfigClient(args.base_url, args.user, args.password, args.server_id, args.dry_run)
    print(f"Target: {client.base} (serverId={args.server_id}){' - DRY RUN' if args.dry_run else ''}")

    if not args.dry_run and not args.no_backup:
        try:
            print(f"Current configuration saved to {backup(client, here)}")
        except (RuntimeError, requests.RequestException) as exc:
            print(f"Backup FAILED - {exc}\nAborting (use --no-backup to force).")
            return 1

    stats = {"applied": 0, "skipped": 0, "failed": 0}
    for name, section, path, part in STEPS:
        if name not in selected or section not in config:
            stats["skipped"] += 1
            print(f"- {name}: skipped")
            continue
        bodies = config[section] if section == "vectorDbServers" else [config[section]]
        for body in bodies:
            label = f"{name}" + (f" (serverId={body.get('serverId')})" if section == "vectorDbServers" else "")
            if args.dry_run:
                print(f"- {label}: POST {path}\n" + json.dumps(mask(body), indent=2))
            try:
                if part:
                    client.post_multipart(path, part, body)
                else:
                    client.post_json(path, body)
                stats["applied"] += 1
                print(f"- {label}: {'would apply' if args.dry_run else 'applied'}")
            except (RuntimeError, requests.RequestException) as exc:
                stats["failed"] += 1
                print(f"- {label}: FAILED - {exc}")

    print("\n== Done ==  " + ", ".join(f"{k}={v}" for k, v in stats.items()))
    return 1 if stats["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
