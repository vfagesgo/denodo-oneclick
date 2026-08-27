#!/bin/bash
## denodo-oneclick install script
## Entry point described in .claude/rules/install.sh.md
##
## Current scope (iteration 1): Docker install mode only, spinning up a
## hello-world placeholder container to validate parameter handling.
## Local install mode is not implemented yet.
set -euo pipefail

# Raw-file base used to fetch install artifacts when this script is run via
# `curl | bash` (no local checkout to read docker/, denodo_config.env from).
# Override with an env var for testing against a fork/branch.
REPO_RAW_BASE="${REPO_RAW_BASE:-https://raw.githubusercontent.com/vfagesgo/denodo-oneclick/main}"

IMAGE_NAME="denodo-oneclick"
IMAGE_TAG="hello-world"

MODE="docker"

# --- 0. Resolve a working directory that has docker/ + denodo_config.env ---
# Local checkout (repo cloned, install.sh run in place): use it as-is.
# Piped install (`curl ... | bash`): there is no local file to derive a
# script directory from, so fetch the required artifacts from GitHub into a
# throwaway temp dir instead of assuming anything exists on disk.
CANDIDATE_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" ]] && [[ -f "${BASH_SOURCE[0]}" ]]; then
  CANDIDATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [[ -n "$CANDIDATE_DIR" ]] && [[ -f "${CANDIDATE_DIR}/docker/Dockerfile" ]]; then
  SCRIPT_DIR="$CANDIDATE_DIR"
else
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/denodo-oneclick.XXXXXX")"
  trap 'rm -rf "$WORK_DIR"' EXIT
  echo "No local checkout found — fetching install artifacts from ${REPO_RAW_BASE}"
  mkdir -p "${WORK_DIR}/docker"
  curl -fsSL "${REPO_RAW_BASE}/docker/Dockerfile" -o "${WORK_DIR}/docker/Dockerfile"
  curl -fsSL "${REPO_RAW_BASE}/docker/entrypoint.sh" -o "${WORK_DIR}/docker/entrypoint.sh"
  curl -fsSL "${REPO_RAW_BASE}/denodo_config.env" -o "${WORK_DIR}/denodo_config.env" || true
  SCRIPT_DIR="$WORK_DIR"
fi

CONFIG_FILE="${SCRIPT_DIR}/denodo_config.env"

usage() {
  cat <<EOF
Usage: install.sh --DENODO_SUPPORT_CI <id> --DENODO_SUPPORT_SECRET <secret> --DENODO_LIC <path-to-license> [options]

Mandatory:
  --DENODO_SUPPORT_CI <value>
  --DENODO_SUPPORT_SECRET <value>
  --DENODO_LIC <path>            Path to the Denodo license file

Overrides (default comes from denodo_config.env):
  --DENODO_UPDATE <value>
  --DENODO_PG_USER <value>
  --DENODO_PG_PWD <value>
  --DENODO_VDP_USER <value>
  --DENODO_VDP_PWD <value>

Optional (CLI only):
  --CLOUDFLARE_TUNNEL_KEY <value>
  --mode <docker|local>          Default: docker (local not implemented yet)
EOF
}

# --- 1. Load defaults from denodo_config.env -------------------------------
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "$CONFIG_FILE"
  set +a
else
  echo "WARNING: ${CONFIG_FILE} not found, continuing with CLI values only." >&2
fi

# --- 2. Parse CLI args (override everything above) -------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --DENODO_SUPPORT_CI) DENODO_SUPPORT_CI="$2"; shift 2 ;;
    --DENODO_SUPPORT_SECRET) DENODO_SUPPORT_SECRET="$2"; shift 2 ;;
    --DENODO_LIC) DENODO_LIC="$2"; shift 2 ;;
    --DENODO_UPDATE) DENODO_UPDATE="$2"; shift 2 ;;
    --DENODO_PG_USER) DENODO_PG_USER="$2"; shift 2 ;;
    --DENODO_PG_PWD) DENODO_PG_PWD="$2"; shift 2 ;;
    --DENODO_VDP_USER) DENODO_VDP_USER="$2"; shift 2 ;;
    --DENODO_VDP_PWD) DENODO_VDP_PWD="$2"; shift 2 ;;
    --CLOUDFLARE_TUNNEL_KEY) CLOUDFLARE_TUNNEL_KEY="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

# --- 3. Validate mandatory parameters ---------------------------------------
missing=()
[[ -z "${DENODO_SUPPORT_CI:-}" ]] && missing+=("--DENODO_SUPPORT_CI")
[[ -z "${DENODO_SUPPORT_SECRET:-}" ]] && missing+=("--DENODO_SUPPORT_SECRET")
[[ -z "${DENODO_LIC:-}" ]] && missing+=("--DENODO_LIC")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "ERROR: missing mandatory parameter(s): ${missing[*]}" >&2
  usage
  exit 1
fi

if [[ ! -f "$DENODO_LIC" ]]; then
  echo "ERROR: DENODO_LIC file not found at: ${DENODO_LIC}" >&2
  exit 1
fi

# --- 4. Dispatch to install mode ---------------------------------------------
case "$MODE" in
  docker) ;;
  local)
    echo "ERROR: local install mode is not implemented yet." >&2
    exit 1
    ;;
  *)
    echo "ERROR: unknown mode '${MODE}' (expected 'docker' or 'local')." >&2
    exit 1
    ;;
esac

echo "== denodo-oneclick: Docker install mode =="

# Rollback safety: keep the previous image under a ':previous' tag instead
# of letting a new build silently replace it.
if docker image inspect "${IMAGE_NAME}:${IMAGE_TAG}" >/dev/null 2>&1; then
  echo "Tagging existing ${IMAGE_NAME}:${IMAGE_TAG} as ${IMAGE_NAME}:previous for rollback."
  docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${IMAGE_NAME}:previous"
fi

docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" "${SCRIPT_DIR}/docker"

# Remove any prior container of the same name so we can re-run install.sh
# idempotently (previous image tag above still allows a rollback).
docker rm -f "${IMAGE_NAME}" >/dev/null 2>&1 || true

docker run --name "${IMAGE_NAME}" --rm \
  -e DENODO_SUPPORT_CI="${DENODO_SUPPORT_CI}" \
  -e DENODO_SUPPORT_SECRET="${DENODO_SUPPORT_SECRET}" \
  -e DENODO_UPDATE="${DENODO_UPDATE:-}" \
  -e DENODO_PG_USER="${DENODO_PG_USER:-}" \
  -e DENODO_PG_PWD="${DENODO_PG_PWD:-}" \
  -e DENODO_VDP_USER="${DENODO_VDP_USER:-}" \
  -e DENODO_VDP_PWD="${DENODO_VDP_PWD:-}" \
  -e CLOUDFLARE_TUNNEL_KEY="${CLOUDFLARE_TUNNEL_KEY:-}" \
  -v "$(cd "$(dirname "$DENODO_LIC")" && pwd)/$(basename "$DENODO_LIC")":/denodo/license.lic:ro \
  "${IMAGE_NAME}:${IMAGE_TAG}"

echo ""
echo "Rollback: docker run/tag ${IMAGE_NAME}:previous to go back to the prior image."
