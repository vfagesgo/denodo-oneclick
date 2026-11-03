#!/usr/bin/env bash
set -euo pipefail

# Resolve paths relative to this script instead of hardcoding an install
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

LOG=/var/log/2-vdb_admin_install.log
sudo touch $LOG
sudo chown -R denodo:denodo "$LOG"
# This installer makes privileged changes across the OS, so fail early on
# missing variables, command failures inside pipelines, and unexpected errors.
set -euo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

log_section() {
  echo "[SECTION $1] $2" | tee -a "$LOG"
}

log_step() {
  echo "[STEP] $1" | tee -a "$LOG"
}

# Optional - only used directly (as an env var) 
# Default it here so `set -u` doesn't crash on it in the gates below, which
OPENAI_API_KEY="${OPENAI_API_KEY:-}"

# Restore the sample DBs
#
# pg_restore exits non-zero whenever it *ignores* any errors while
# restoring (e.g. "role ... does not exist" for ownership/ACL statements
# skipped by --no-owner) - even when the restore itself completes fine.
# Under `set -e` that non-zero exit would kill the whole install over
# warnings pg_restore already decided were safe to skip, so it's
# explicitly tolerated here with `|| true`.
log_step "Restoring sample database: pharma (ignored-error warnings from pg_restore are expected and non-fatal)"
sudo -u postgres psql -d denodo -c "DROP SCHEMA IF EXISTS pharma CASCADE;"
sudo -u postgres pg_restore --jobs=4 --no-owner -d denodo /opt/denodo-oneclick/samples/dump-pharma.dump || true

log_step "Restoring sample database: bank (ignored-error warnings from pg_restore are expected and non-fatal)"
sudo -u postgres psql -d denodo -c "DROP SCHEMA IF EXISTS bank CASCADE;"
sudo -u postgres pg_restore --jobs=4 --no-owner -d denodo /opt/denodo-oneclick/samples/dump-bank.dump || true

log_step "Restoring sample database: c_api_gp_details_service (ignored-error warnings from pg_restore are expected and non-fatal)"
sudo -u postgres pg_restore --jobs=4 --no-owner --clean --if-exists -d denodo /opt/denodo-oneclick/samples/c_api_gp_details_service.dump || true


sudo -u postgres psql -d denodo <<'SQL'
GRANT ALL ON SCHEMA pharma TO denodo;
GRANT ALL ON SCHEMA public TO denodo;
GRANT ALL ON SCHEMA bank TO denodo;

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA pharma TO denodo;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO denodo;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA bank TO denodo;

GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA pharma TO denodo;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO denodo;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA bank TO denodo;

ALTER DEFAULT PRIVILEGES IN SCHEMA pharma
    GRANT ALL ON TABLES TO denodo;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL ON TABLES TO denodo;
ALTER DEFAULT PRIVILEGES IN SCHEMA bank
    GRANT ALL ON TABLES TO denodo;

ALTER DEFAULT PRIVILEGES IN SCHEMA pharma
    GRANT ALL ON SEQUENCES TO denodo;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL ON SEQUENCES TO denodo;
ALTER DEFAULT PRIVILEGES IN SCHEMA bank
    GRANT ALL ON SEQUENCES TO denodo;
SQL



# Section 17.5:
# Import the sample metadata (the pharma/bank/etc. demo databases) into
# Denodo VDP now that it's confirmed up.
log_step "Denodo VDP is running"
log_section "17.5" "Import Denodo Metadata"

export_properties="/opt/denodo-oneclick/samples/full_export/fullExport.properties"
sed -i "s|<OpenAI_apiKey>|$OPENAI_API_KEY|g" $export_properties

#Copy assets extensions samples
unzip -o /opt/denodo-oneclick/samples/asset_extensions.zip -d /opt/denodo/denodo-platform/samples/
unzip -o /opt/denodo-oneclick/samples/skills.zip -d /opt/denodo/denodo-platform/samples/

/opt/denodo/denodo-platform/bin/import.sh --singleuser --file /opt/denodo-oneclick/samples/full_export/fullExport.vql --properties-file $export_properties --server localhost:9999/admin?admin@$DENODO_VDP_PWD --metadata-password=password 
#/opt/denodo/denodo-platform/bin/import.sh --singleuser --file /opt/denodo-oneclick/samples/admin_export.zip --server localhost:9999/admin?admin@$DENODO_VDP_PWD --metadata-password=password
#/opt/denodo/denodo-platform/bin/import.sh --singleuser --file /opt/denodo-oneclick/samples/asset_extensions_export.zip --server localhost:9999/admin?admin@$DENODO_VDP_PWD --metadata-password=password
#/opt/denodo/denodo-platform/bin/import.sh --singleuser --file /opt/denodo-oneclick/samples/pharm_ai_export.zip --server localhost:9999/admin?admin@$DENODO_VDP_PWD --metadata-password=password
#/opt/denodo/denodo-platform/bin/import.sh --singleuser --file /opt/denodo-oneclick/samples/bank_demo_export.zip --server localhost:9999/admin?admin@$DENODO_VDP_PWD --metadata-password=password
#/opt/denodo/denodo-platform/bin/import.sh --singleuser --file /opt/denodo-oneclick/samples/aws_tpcds_export.zip --server localhost:9999/admin?admin@$DENODO_VDP_PWD --metadata-password=password


log_step "Waiting for Denodo DM to start"
until curl -fsS "http://localhost:9090/denodo-data-catalog/#/" >/dev/null 2>&1; do
  if [ "$VDP_WAITED" -ge "$VDP_TIMEOUT" ]; then
    log_step "ERROR: Denodo Data Marketplace did not start within ${VDP_TIMEOUT} seconds"
    exit 1
  fi

  sleep 2
  VDP_WAITED=$((VDP_WAITED + 2))
done

# Section 17.6:
# Now that Denodo Data Marketplace is confirmed up, tell it to synchronize
# with VDP - both the full metadata sync and the ai_ready tag sync that the
# AI SDK relies on later.
log_step "Denodo Data Marketplace is running"
log_section "17.6" "Synchronizing Denodo Metadata"

# NOTE: the sync must run as `if response=$(curl ...); then ... else ... fi`
# (the curl call as the if's own condition), not `response=$(curl ...)`
# followed by a separate `if [ $? -eq 0 ]`: under `set -e`, a plain
# assignment statement's command substitution failing exits the script
# immediately, right there, before a later `if [ $? -eq 0 ]` is ever
# reached - making that "gentle failure" branch dead code and turning any
# sync hiccup into a hard install failure. Putting the assignment directly
# in the if's condition is exempt from `set -e` by design, so a failure
# here is just logged as a warning and the install continues.
if response=$(curl --silent --show-error --fail  \
  --request 'POST' \
  --header 'accept: */*' \
  --user "admin:$DENODO_VDP_PWD" \
  --header 'Content-Type: application/json' \
  --header 'uri: //localhost:9999/admin' \
  --header 'serverId: 1' \
  --data '{
    "allServers": "true",
    "priority": "server"
  }' \
"http://localhost:9090/denodo-data-catalog/public/api/element-management/all/synchronize/all-servers"); then
  log_step "Data Marketplace sync (all-servers): SUCCESS"
else
  log_step "WARNING: Data Marketplace sync (all-servers) failed - continuing anyway"
  echo "$response" | tee -a "$LOG"
fi

if response=$(curl --silent --show-error --fail  \
  --request 'POST' \
  --header 'accept: */*' \
  --user "admin:$DENODO_VDP_PWD" \
  --header 'Content-Type: application/json' \
  --header 'uri: //localhost:9999/admin' \
  --header 'serverId: 1' \
  --data '{
  "vdpTags": [
    "ai_ready"
  ]
}' \
"http://localhost:9090/denodo-data-catalog/public/api/tags/vdp/synchronize"); then
  log_step "Data Marketplace sync (tags): SUCCESS"
else
  log_step "WARNING: Data Marketplace sync (tags) failed - continuing anyway"
  echo "$response" | tee -a "$LOG"
fi


### import data marketplace metadata
#/opt/denodo/denodo-platform/tools/data-catalog/import.sh -h localhost -override -p 9090 -l admin -P admin -f /opt/denodo-oneclick/samples/data_marketplace.zip
#/opt/denodo/denodo-platform/tools/data-catalog/import.sh -h localhost -override -pw password -p 9090 -l admin -P admin -f /opt/denodo-oneclick/samples/dc-metadata.zip


# Load the AI SDK's metadata into its vector DB, so it can answer natural-
# language questions about the sample data. The AI SDK needs a valid
# OPENAI_API_KEY to start at all (Section 13 just wrote whatever was passed
# on this run into sdk_config.env/chatbot_config.env) - without one it would
# just crash on start, and the "Waiting for AI SDK to start" loop below
# would spend the full timeout waiting for something that's never coming up
# before failing the whole script. Check the config file itself
# (aisdk_has_openai_key(), defined near the top) rather than the
# OPENAI_API_KEY env var directly, so an --upgrade that doesn't repeat
# --OPENAI_API_KEY still correctly starts the AI SDK if a key was configured
# on an earlier run.
if aisdk_has_openai_key; then
  start_denodo_ai_services
  log_step "Waiting for AI SDK to start"
  until curl -fsS "http://localhost:8008/docs" >/dev/null 2>&1; do
    if [ "$VDP_WAITED" -ge "$VDP_TIMEOUT" ]; then
      log_step "ERROR: Denodo AI SDK did not start within ${VDP_TIMEOUT} seconds"
      exit 1
    fi

    sleep 2
    VDP_WAITED=$((VDP_WAITED + 2))
  done
  log_step "Denodo AI SDK is running"
  log_section "17.7" "Synchronizing AI SDK Metadata"
  # Same `if var=$(curl ...); then` pattern as the Data Marketplace sync
  # above, and for the same reason: keeps a sync failure from being a hard
  # `set -e` exit instead of the warning it's meant to be.
  if response=$(curl --silent --show-error --fail \
    --request GET \
    --header 'accept: */*' \
    --user "admin:$DENODO_VDP_PWD" \
    --header 'Content-Type: application/json' \
    "http://localhost:8008/getMetadata?vdp_tag_names=ai_ready"); then
    log_step "AI SDK metadata sync: SUCCESS"
  else
    log_step "WARNING: AI SDK metadata sync failed - continuing anyway"
    echo "$response" | tee -a "$LOG"
  fi
else
  log_step "No OPENAI_API_KEY configured for the AI SDK - skipping its start and vector DB metadata sync"
fi