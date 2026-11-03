#!/usr/bin/env bash
set -euo pipefail

# Resolve paths relative to this script so data files can be found no matter
# what the caller's working directory is.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

vdb_name="asset_extensions"

LOG="/var/log/2-vdb_${vdb_name}_install.log"
sudo touch "$LOG"
sudo chown -R denodo:denodo "$LOG"

# Fail early on missing variables, failed pipeline commands, and unexpected
# errors, and report the offending line.
trap 's=$?; echo "$0: Error on line $LINENO: $BASH_COMMAND"; exit $s' ERR

log_section() { echo "[SECTION $1] $2" | tee -a "$LOG"; }
log_step()    { echo "[STEP] $1"      | tee -a "$LOG"; }

# Parameters inherited from the main installer (exported there). Defaults are
# provided so this script can also be run on its own.
DENODO_VDP_PWD="${DENODO_VDP_PWD:-admin}"

VDP_TIMEOUT=300
VDP_WAITED=0

export_properties="vdb_${vdb_name}_Export.properties"
export_vql="vdb_${vdb_name}_Export.vql"

# Where the Denodo platform expects the local sample files to live. The export
# property file references the CSVs as "../samples/asset_extensions/*.csv"
# (relative to the VDP server working directory), so the data_sources/ files
# shipped with this script are copied there under that name.
PLATFORM_SAMPLES="/opt/denodo/denodo-platform/samples"

# ---------------------------------------------------------------------------
log_section "0" "Prepare the sample data"

log_step "Copying asset-extension sample data to $PLATFORM_SAMPLES/asset_extensions"
rm -rf "$PLATFORM_SAMPLES/asset_extensions"
cp -r "$SCRIPT_DIR/data_sources" "$PLATFORM_SAMPLES/asset_extensions"

log_step "Copying skills to $PLATFORM_SAMPLES/skills"
rm -rf "$PLATFORM_SAMPLES/skills"
cp -r "$SCRIPT_DIR/skills" "$PLATFORM_SAMPLES/skills"

# ---------------------------------------------------------------------------
log_section "1" "Wait for Denodo VDP to start"

until (echo > /dev/tcp/localhost/9999) >/dev/null 2>&1; do
  if [ "$VDP_WAITED" -ge "$VDP_TIMEOUT" ]; then
    log_step "ERROR: Denodo VDP did not start within ${VDP_TIMEOUT} seconds"
    exit 1
  fi
  sleep 4
  VDP_WAITED=$((VDP_WAITED + 2))
done
log_step "Denodo VDP is listening on TCP port 9999"

# ---------------------------------------------------------------------------
log_section "2" "Import Denodo metadata"

/opt/denodo/denodo-platform/bin/import.sh --singleuser \
  --file "$SCRIPT_DIR/$export_vql" \
  --properties-file "$SCRIPT_DIR/$export_properties" \
  --server "localhost:9999/admin?admin@$DENODO_VDP_PWD" \
  --metadata-password=password

# ---------------------------------------------------------------------------
log_section "3" "Wait for Denodo Data Marketplace to start"

until curl -fsS "http://localhost:9090/denodo-data-catalog/#/" >/dev/null 2>&1; do
  if [ "$VDP_WAITED" -ge "$VDP_TIMEOUT" ]; then
    log_step "ERROR: Denodo Data Marketplace did not start within ${VDP_TIMEOUT} seconds"
    exit 1
  fi
  sleep 2
  VDP_WAITED=$((VDP_WAITED + 2))
done
log_step "Denodo Data Marketplace is running"

# ---------------------------------------------------------------------------
log_section "4" "Synchronize Data Marketplace metadata"

# Each sync runs as the condition of an `if` (`if response=$(curl ...); then`)
# rather than a plain assignment followed by `if [ $? -eq 0 ]`. Under `set -e`
# a failing command substitution in a plain assignment exits the script
# immediately, making the "gentle failure" branch dead code; using it as the
# `if` condition is exempt from `set -e`, so a sync hiccup is logged as a
# warning and the install continues.
if response=$(curl --silent --show-error --fail \
  --request POST \
  --header 'accept: */*' \
  --user "admin:$DENODO_VDP_PWD" \
  --header 'Content-Type: application/json' \
  --header 'uri: //localhost:9999/admin' \
  --header 'serverId: 1' \
  --data '{"allServers": "true", "priority": "server"}' \
  "http://localhost:9090/denodo-data-catalog/public/api/element-management/all/synchronize/all-servers"); then
  log_step "Data Marketplace sync (all-servers): SUCCESS"
else
  log_step "WARNING: Data Marketplace sync (all-servers) failed - continuing anyway"
  echo "$response" | tee -a "$LOG"
fi

if response=$(curl --silent --show-error --fail \
  --request POST \
  --header 'accept: */*' \
  --user "admin:$DENODO_VDP_PWD" \
  --header 'Content-Type: application/json' \
  --header 'uri: //localhost:9999/admin' \
  --header 'serverId: 1' \
  --data '{"vdpTags": ["ai_ready"]}' \
  "http://localhost:9090/denodo-data-catalog/public/api/tags/vdp/synchronize"); then
  log_step "Data Marketplace sync (tags): SUCCESS"
else
  log_step "WARNING: Data Marketplace sync (tags) failed - continuing anyway"
  echo "$response" | tee -a "$LOG"
fi

# ---------------------------------------------------------------------------
log_section "4.5" "Update Data Marketplace metadata"

#python "$SCRIPT_DIR/../DM_import_tools/1_import_domains.py"         --file "$SCRIPT_DIR/1_${vdb_name}_domains.json" --base-url http://localhost/denodo-data-catalog --user admin --password $DENODO_VDP_PWD --server-id 1
#python $SCRIPT_DIR/../DM_import_tools/2_import_property_groups.py"  --file "$SCRIPT_DIR/2_${vdb_name}_property_groups.json" --base-url http://localhost/denodo-data-catalog --user admin --password $DENODO_VDP_PWD --server-id 1
#python $SCRIPT_DIR/../DM_import_tools/3_assign_domains.py"          --file "$SCRIPT_DIR/3_${vdb_name}_domain_assignments.json" --base-url http://localhost/denodo-data-catalog --user admin --password $DENODO_VDP_PWD --server-id 1
#python $SCRIPT_DIR/../DM_import_tools/4_assign_property_groups.py"  --file "$SCRIPT_DIR/4_${vdb_name}_property_assignments.json" --base-url http://localhost/denodo-data-catalog --user admin --password $DENODO_VDP_PWD --server-id 1
python $SCRIPT_DIR/../DM_import_tools/5_import_asset_extensions.py" --file "$SCRIPT_DIR/5_asset_extensions.json" --base-url http://localhost/denodo-data-catalog --user admin --password $DENODO_VDP_PWD --server-id 1

# ---------------------------------------------------------------------------
log_section "5" "Wait for Denodo AI SDK to start"

until curl -fsS "http://localhost:8008/docs" >/dev/null 2>&1; do
  if [ "$VDP_WAITED" -ge "$VDP_TIMEOUT" ]; then
    log_step "ERROR: Denodo AI SDK did not start within ${VDP_TIMEOUT} seconds"
    exit 1
  fi
  sleep 2
  VDP_WAITED=$((VDP_WAITED + 2))
done
log_step "Denodo AI SDK is running"

# ---------------------------------------------------------------------------
log_section "6" "Synchronize AI SDK metadata"

# Load the AI SDK's metadata into its vector DB so it can answer natural-
# language questions about the sample data. Same `if response=$(curl ...)`
# pattern as above, for the same reason.
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
