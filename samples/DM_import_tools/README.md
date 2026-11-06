# Denodo Data Catalog / Data Marketplace import tools

A set of Python scripts that create or update catalog metadata in the Denodo
Data Catalog / Data Marketplace through its public REST API (`dm-api-docs.json`).
Each script reads a JSON file (by default the one next to it) and is **idempotent**:
existing items are updated only when something differs, missing ones are created.

Run them in numeric order — later scripts depend on what earlier ones create:

| # | Script | Creates / updates | Default input |
|---|--------|-------------------|---------------|
| 1 | `1_import_domains.py` | Domain (category) tree | `1_domains.json` |
| 2 | `2_import_property_groups.py` | Property groups & properties | `2_property_groups.json` |
| 3 | `3_assign_domains.py` | Assign views / web services / assets to domains | `3_domain_assignments.json` |
| 4 | `4_assign_property_groups.py` | Assign property groups & set values on elements | `4_property_assignments.json` |
| 5 | `5_import_asset_extensions.py` | Asset-extension types, provider types, tool servers | `5_asset_extensions.json` |
| 6 | `6_import_dm-config.py` | Admin configuration: LLM, Vector DB, Denodo Assistant | `_6_dm-config.json` |

Script 6 is independent of 1–5 (global admin settings, not catalog content) and
can be run on its own.

## Requirements

```shell
pip install requests
```

Scripts 3, 4 and 5 reuse the shared HTTP client and the name→id resolution in
`3_assign_domains.py`, so keep all scripts in the same folder.

## Common options

Every script accepts the same connection flags (shown with their defaults; each
also reads an environment variable):

| Flag | Env var | Default |
|------|---------|---------|
| `--base-url URL` | `DENODO_DC_URL` | `http://localhost/denodo-data-catalog` |
| `--user NAME` | `DENODO_USER` | `admin` |
| `--password PWD` | `DENODO_PASSWORD` | `admin` |
| `--server-id N` | `DENODO_SERVER_ID` | `1` |
| `--file PATH` | – | the `*.json` next to the script |
| `--dry-run` | – | read only: print what would change, write nothing |

Authentication is HTTP Basic; the `serverId` query parameter is sent on every call.

## Quick start

```shell
python 1_import_domains.py          --base-url http://localhost/denodo-data-catalog --user admin --password admin --server-id 1
python 2_import_property_groups.py  --base-url http://localhost/denodo-data-catalog --user admin --password admin --server-id 1
python 3_assign_domains.py          --base-url http://localhost/denodo-data-catalog --user admin --password admin --server-id 1
python 4_assign_property_groups.py  --base-url http://localhost/denodo-data-catalog --user admin --password admin --server-id 1
python 5_import_asset_extensions.py --base-url http://localhost/denodo-data-catalog --user admin --password admin --server-id 1 --sync
OPENAI_API_KEY=sk-... \
python 6_import_dm-config.py        --base-url http://localhost/denodo-data-catalog --user admin --password admin --server-id 1
```

---

## 1 — `1_import_domains.py`

Imports a recursive **Domain (category) tree**.

API: `GET/POST /category-management/categories`, `PUT /category-management/categories/{id}`.

A category is identified by `(name, parentId)`. Parents are processed before
their children so each child receives the real parent id. An existing category
is updated only if its description differs; a failure on one node is reported and
its sub-tree skipped while the rest of the import continues. An HTML description
is sent as `RICH_TEXT`, plain text as `TEXT`.

Input JSON — a list of nodes, `subdomains` nests to any depth:

```json
[
  { "name": "Operations",
    "description": "<p>Operational domains</p>",
    "subdomains": [
      { "name": "Manufacturing", "description": "...", "subdomains": [] }
    ] }
]
```

Extra option: none beyond the common ones.

```shell
python3 1_import_domains.py [--file 1_domains.json] [--dry-run] <connection flags>
```

## 2 — `2_import_property_groups.py`

Imports custom **Property Groups** and their **Properties** (it does *not* assign
them to any element — that is script 4).

API: `GET/POST/PUT /property-management/groups`, `.../groups/{id}/properties`,
`PUT /property-management/properties`, plus a compatibility pre-check and a sort
call to keep the JSON order.

Groups are matched by name; properties by name within their group. Existing items
are updated only when a field differs. Enumeration values removed from
`possibleValues` are deleted on the server, with the property's `defaultValue` as
replacement.

Input JSON:

```json
[
  { "name": "Data Product Details", "description": "...",
    "descriptionType": "TEXT",
    "placeToShow": "SPECIFIC_CUSTOM_PROPERTY_TAB",
    "aiUsageEnabled": true,
    "properties": [
      { "name": "Status", "description": "...", "descriptionType": "TEXT",
        "type": "ENUMERATION", "interpolable": false, "defaultValue": "Active",
        "possibleValues": ["Active", "Deprecated"] }
    ] }
]
```

`type` is one of `TEXT | LONG_TEXT | RICH_TEXT | ENUMERATION`; `possibleValues`
applies to `ENUMERATION` only.

Extra options:

- `--update-assignments` — propagate property changes to elements already using
  them (`updateAssignments=true`).
- `--no-sort` — do not reorder properties to match the JSON order.

```shell
python3 2_import_property_groups.py [--file 2_property_groups.json] \
    [--update-assignments] [--no-sort] [--dry-run] <connection flags>
```

## 3 — `3_assign_domains.py`

Assigns **views, web services and asset extensions** to domain categories.
Run `1_import_domains.py` first.

API: assignment is additive via `POST .../categories/{id}/{views|webservices|external-elements}`;
removal (with `--prune`) via the matching `DELETE`.

**Additive by default.** Items already in a domain are left alone; only missing
ones are added. Two input files can be applied one after the other without the
second undoing the first.

**`--prune`** removes items that are in a listed domain but not in the JSON. It is
scoped to the domains named in the file, and it is skipped for any domain that has
unresolved references (so it never deletes something it merely could not see).

The domain is a **path** (list of names from the root), because the same name can
exist under different parents. Elements are referenced as `"database.name"` or
`{"id": N}` (assets also accept `{"name": "..."}`).

Input JSON:

```json
[
  { "domain": ["Pharma / Life Sciences", "Clinical Trials"],
    "views":       ["pharm_ai.clinical_trials", {"id": 42}],
    "webservices": ["pharm_ai.ws_patients"],
    "assets":      ["TrialPulse: 360 Patient Insights", {"id": 7}] }
]
```

Extra options: `--prune`, `--debug`.

```shell
python3 3_assign_domains.py [--file 3_domain_assignments.json] \
    [--prune] [--dry-run] [--debug] <connection flags>
```

## 4 — `4_assign_property_groups.py`

Assigns the **property groups** from script 2 to views, web services and asset
extensions, and **sets their property values**. Run scripts 2 and 3 first.

API: `POST .../{views|webservices|external-elements}/{id}/groups` (group
assignment), `PUT /property-management/elements/properties` /
`POST /property-management/assign-property-to-elements` (values), and, with
`--prune`, `DELETE .../groups/{groupId}/elements/...` to unassign a group.

**Additive by default.** Group assignments are merged with whatever the element
already has, and only values that differ are written — so `bank_demo` then
`pharm_ai` can be applied in sequence without the second run undoing the first.
Within a single file, entries are applied in order and a later entry overrides an
earlier one for the same element (useful for exceptions such as PII views).

**`--prune`** removes any property group an element still has that is not listed
for it in the JSON (unassigning a group also clears that group's values on the
element). It is scoped to the elements present in the file, so running one file
never touches elements managed by another.

Values are validated against the server before any change: group/property names
must exist, enumeration values must be allowed options, max 4000 characters.

Input JSON:

```json
[
  { "comment": "free text, ignored",
    "views":       ["bank_demo.customers"],
    "webservices": ["bank_demo.bank_demo_rest_ws"],
    "assets":      ["TrialPulse: 360 Patient Insights"],
    "groups": {
      "Data Product Details": { "Status": "Active",
                                "Domain": "Sales & Commercial > Account Management" },
      "Data Product Owners": {}
    } }
]
```

A group mapped to `{}` is assigned with its default values. Extra options:
`--prune`, `--debug`.

```shell
python3 4_assign_property_groups.py [--file 4_property_assignments.json] \
    [--prune] [--dry-run] [--debug] <connection flags>
```

## 5 — `5_import_asset_extensions.py`

Imports the **asset-extension building blocks**: element (external-element) types,
external **provider types** (name + visual name + icon), and **tool servers**
(CUSTOM type, mapping a provider type to a VDP interface view).

API: `GET/POST/PUT /external-elements-types`, `.../external-providers-types`
(multipart, with the icon), `.../external-tool-servers`, plus the optional
synchronize endpoints.

Everything is matched by name (types by technical name, servers by server name).
Existing items are updated when a field differs — including the provider icon when
the API returns it — otherwise created. Use `--force` to update every existing
item regardless.

Input JSON:

```json
{ "elementTypes":  [ { "name": "...", "visualName": "...", "description": "...",
                       "iconKey": "...", "iconColorCode": "...",
                       "reversedIconColorCode": "..." } ],
  "providerTypes": [ { "name": "QLIK", "visualName": "Qlik",
                       "icon": "icons/qlik_provider.svg" } ],
  "toolServers":   [ { "name": "...", "description": "...",
                       "databaseName": "...", "viewName": "...",
                       "providerType": "QLIK",
                       "sync": false } ] }
```

Icon paths are relative to the JSON file. A tool server references its provider by
`providerType` (name) or `providerTypeId` (id); `sync: false` excludes it from
`--sync`.

Extra options:

- `--only element-types|provider-types|tool-servers` — import just one section.
- `--force` — update existing items even when no difference is detected.
- `--sync` — synchronize the tool servers listed in the JSON afterwards.
- `--sync-vdp` — synchronize VDP elements into the catalog first (before `--sync`).
- `--no-import` — skip the JSON import and only synchronize (needs `--sync` and/or
  `--sync-vdp`). In this mode no input file is read, and `--sync` synchronizes
  **every tool server already present in the catalog**.
- `--strict` — exit non-zero when any item fails to import or any server fails to
  synchronize. By default the run is **best-effort and exits 0**: individual
  failures (e.g. a server whose VDP metadata view errors, or one the API reports
  with a null `id`) are logged as warnings and do not fail the run, so a calling
  install script running under `set -e` is not aborted. Use `--strict` in CI.
- `--debug` — print raw samples of API answers.

```shell
python3 5_import_asset_extensions.py [--file 5_asset_extensions.json] \
    [--only ...] [--force] [--sync] [--sync-vdp] [--no-import] [--dry-run] [--debug] <connection flags>
```

To synchronize only, without importing anything:

```shell
python3 5_import_asset_extensions.py --no-import --sync             # sync all catalog tool servers
python3 5_import_asset_extensions.py --no-import --sync-vdp --sync  # sync VDP elements first, then servers
```

## 6 — `6_import_dm-config.py`

Applies the **Data Marketplace admin configuration**: LLM and thinking LLM,
Vector DB (connection, embedding model, indexed VDP servers) and the Denodo
Assistant (assisted query, chatbot, agent skills).

API:

| Step (`--only`) | JSON section | Endpoint |
|-----------------|--------------|----------|
| `llm` | `llmConfiguration` | `POST /configuration/llm-configuration` (multipart) |
| `vectordb` | `vectorDbConfiguration` | `POST /configuration/vectordb-integration/api-configuration` (multipart) |
| `servers` | `vectorDbServers` (list) | `POST /configuration/vectordb-integration/vdp-server` (one call per server) |
| `assisted-query` | `assistedQuery` | `POST /configuration/ai-integration/assisted-query` |
| `chatbot` | `chatbot` | `POST /configuration/personalization/denodo-assistant/chatbot` |

Each section is sent **as-is** as the request body (schemas
`LlmDualConfigurationRequest`, `VectorDbConfigurationRequest`,
`VectorDbConfigureVdpServerRequest`, `AssistedQueryConfigurationRequest`,
`ChatbotConfigurationRequest`). Steps run in the order above; a section missing
from the JSON is skipped. Unlike scripts 1–5 there is no diff: every selected
section is posted (the API replaces the configuration).

**Secrets.** Any string `"${VAR}"` is replaced by the environment variable `VAR`
when it is set (e.g. `"apiKey": "${OPENAI_API_KEY}"`); otherwise a warning is
printed and the literal is sent. Keys starting with `_` (e.g. `_comment`,
`_endpoint`) are ignored. Passwords / API keys are masked in `--dry-run` output.

**Backup (rollback).** Before applying, the current configuration returned by
`GET /configuration/configuration-details` is saved to
`_6_dm-config.backup-<timestamp>.json` next to the script; the run aborts if the
backup fails. The backup is the raw API answer — restoring it is a manual step.

Input JSON (abridged):

```json
{ "llmConfiguration": {
    "llmConfiguration":         { "aiServiceType": "OPENAI",
                                  "openAiConfiguration": { "authenticationType": "API_KEY",
                                    "apiKey": "${OPENAI_API_KEY}", "modelName": "gpt-5.4-mini", ... } },
    "thinkingLlmConfiguration": { "thinkingEnabled": true, "aiServiceType": "OPENAI",
                                  "openAiConfiguration": { ..., "modelName": "gpt-5.5",
                                                           "reasoningEffort": "medium" } },
    "proxyConfiguration":       { "enabled": false, "host": "", "port": 0 } },
  "vectorDbConfiguration": {
    "enabled": true,
    "dbConnectionConfiguration":   { "connectionProvider": "PG_VECTOR",
                                     "pgVectorConfiguration": { "url": "jdbc:postgresql://localhost:5432/denodo",
                                       "username": "denodo", "password": "password",
                                       "authenticationType": "LOGIN_PASSWORD" } },
    "embeddingModelConfiguration": { "embeddingModelProvider": "OPENAI",
                                     "openAiConfiguration": { "modelName": "text-embedding-3-small", ... } },
    "indexConfiguration":          { "batchSize": 100, "refreshMetadataInterval": 60 } },
  "vectorDbServers": [ { "serverId": 1, "enabled": true, "username": "admin", "password": "password",
                         "dataUsageEnabled": true, "dataUsageSampleSize": 10,
                         "externalElementsConfiguration": { "enabled": true, "tags": [] } } ],
  "assistedQuery": { "enabled": true, "dataUsageEnabled": true, ... },
  "chatbot":       { "enabled": true,
                     "customInstructionsConfiguration": { "enabled": true, "content": "..." },
                     "skillsConfiguration": { "enabled": true, "allowedTags": [] } } }
```

UI label → JSON field mapping for the less obvious ones: *Use sample data* →
`dataUsageEnabled`; *Enable asset extensions* → `externalElementsConfiguration.enabled`;
*Enable server metadata vectorization* → `vectorDbServers[].enabled`.

Extra options:

- `--only llm,vectordb,servers,assisted-query,chatbot` — apply a subset of steps.
- `--no-backup` — do not save the current configuration first.

```shell
python3 6_import_dm-config.py [--file _6_dm-config.json] [--only ...] \
    [--no-backup] [--dry-run] <connection flags>
```

From an install script:

```shell
export OPENAI_API_KEY="sk-..."
"$PYTHON" "$SCRIPT_DIR/../DM_import_tools/6_import_dm-config.py" \
  --base-url http://localhost/denodo-data-catalog \
  --user admin --password "$DENODO_VDP_PWD" --server-id 1
```
