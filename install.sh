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
# Single volume: entrypoint.sh mounts everything that needs to persist
# (repo checkout, downloads, Denodo install, AI SDK, Postgres data) as
# symlinks into subdirectories of /data instead of one volume per path.
VOLUME_NAME="denodo-oneclick-data"

MODE="docker"
RESET=0
ACTION=""

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
  --reset                        Wipe any existing container + its volumes first,
                                  so the install starts truly from scratch

Actions on an existing container (instead of building/running one):
  --refresh                      Pull the latest denodo-oneclick repo into the
                                  running container and reapply its nginx/
                                  service config, then restart services. Does
                                  not touch the installed Denodo software.
  --upgrade                      Like --refresh, but also re-runs the Denodo
                                  platform installer if --DENODO_UPDATE changed,
                                  and always re-fetches the AI SDK and MCP
                                  server. Needs --DENODO_SUPPORT_CI/--DENODO_SUPPORT_SECRET.
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
    --reset) RESET=1; shift ;;
    --refresh) ACTION="refresh"; shift ;;
    --upgrade) ACTION="upgrade"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

# --- 2.5. --refresh / --upgrade: act on an existing container, then exit ---
# These don't build or run anything - they reach into an already-running
# install via `docker exec` and ask linux/install.sh to do less than a full
# install (see that script's DENODO_ACTION for what each one actually does).
if [[ -n "$ACTION" ]]; then
  if [[ "$RESET" -eq 1 ]]; then
    echo "ERROR: --reset can't be combined with --refresh/--upgrade - reset starts a fresh install instead." >&2
    exit 1
  fi

  if ! docker inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
    echo "ERROR: no existing '${IMAGE_NAME}' container found - run a normal install first." >&2
    exit 1
  fi

  if [[ "$ACTION" == "upgrade" ]]; then
    missing=()
    [[ -z "${DENODO_SUPPORT_CI:-}" ]] && missing+=("--DENODO_SUPPORT_CI")
    [[ -z "${DENODO_SUPPORT_SECRET:-}" ]] && missing+=("--DENODO_SUPPORT_SECRET")
    if [[ ${#missing[@]} -gt 0 ]]; then
      echo "ERROR: --upgrade needs ${missing[*]} (used to fetch the update/AI SDK/MCP archives)." >&2
      exit 1
    fi
  fi

  if [[ "$(docker inspect -f '{{.State.Running}}' "${IMAGE_NAME}")" != "true" ]]; then
    echo "Container '${IMAGE_NAME}' is stopped - starting it first."
    docker start "${IMAGE_NAME}" >/dev/null
    # entrypoint.sh runs its own git fetch/reset + chown on every boot,
    # racing the exec-based refresh below if it starts immediately -
    # `docker start` returns as soon as the container's process launches,
    # not once entrypoint.sh's own repo sync/services-only pass has
    # finished. Give it a head start so the two don't touch the repo
    # directory at the same time (which can leave ownership in a state
    # that trips git's "dubious ownership" check right back up).
    echo "Waiting for the container's own startup sequence to settle..."
    sleep 20
  fi

  echo "== denodo-oneclick: ${ACTION} =="

  # Repo ownership inside the container can drift back to root between
  # restarts (a bug in an older entrypoint.sh - now fixed there too, but
  # already-running containers won't pick that fix up until their next full
  # restart). git then refuses to touch the directory as "denodo" with a
  # "dubious ownership" error. Reassert ownership + mark it safe for git
  # unconditionally here so --refresh/--upgrade work regardless of whether
  # the container has been restarted since that fix landed.
  docker exec -u root "${IMAGE_NAME}" bash -c '
    # -H: /opt/denodo-oneclick is a symlink to /data/repo - without it,
    # `chown -R` only reowns that target directory itself, not its
    # contents (e.g. .git/), which is exactly what caused
    # "cannot open .git/FETCH_HEAD: Permission denied" here.
    chown -R -H denodo:denodo /opt/denodo-oneclick
    # The chown above recurses into www/ too, undoing the www-data
    # group/permissions nginx needs to serve it (see the matching comment
    # in docker/entrypoint.sh) - reapply them.
    if [ -d /opt/denodo-oneclick/www ]; then
      chgrp -R www-data /opt/denodo-oneclick/www
      chmod -R 750 /opt/denodo-oneclick/www
    fi
    sudo -H -u denodo git config --global --get-all safe.directory 2>/dev/null | grep -qx "*" \
      || sudo -H -u denodo git config --global --add safe.directory "*"
  '

  echo "Pulling the latest denodo-oneclick repo into the container and running linux/install.sh --${ACTION}..."
  docker exec \
    -e DENODO_ACTION="${ACTION}" \
    -e DENODO_SUPPORT_CI="${DENODO_SUPPORT_CI:-}" \
    -e DENODO_SUPPORT_SECRET="${DENODO_SUPPORT_SECRET:-}" \
    -e DENODO_LIC="${DENODO_LIC:-}" \
    -e DENODO_UPDATE="${DENODO_UPDATE:-}" \
    -e DENODO_PG_USER="${DENODO_PG_USER:-}" \
    -e DENODO_PG_PWD="${DENODO_PG_PWD:-}" \
    -e DENODO_VDP_USER="${DENODO_VDP_USER:-}" \
    -e DENODO_VDP_PWD="${DENODO_VDP_PWD:-}" \
    -u denodo \
    "${IMAGE_NAME}" bash -c '
      set -e
      cd /opt/denodo-oneclick
      git fetch origin
      git reset --hard origin/main
      git clean -fd
      bash linux/install.sh
    '
  rc=$?

  if [[ $rc -ne 0 ]]; then
    echo "ERROR: --${ACTION} failed (exit ${rc}). Check the logs: docker logs -f ${IMAGE_NAME}" >&2
    exit "$rc"
  fi

  echo ""
  echo "--${ACTION} completed."
  exit 0
fi

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

if [[ "$RESET" -eq 1 ]]; then
  # Manually running `docker rm -f` + `docker volume rm ...` (the command
  # printed at the end of a normal run) is easy to get wrong - miss one
  # volume name and the "fresh" container silently reattaches to old state.
  # This does the full, reliable teardown in one step.
  echo "--reset: removing any existing '${IMAGE_NAME}' container and its volume"
  docker rm -f "${IMAGE_NAME}" >/dev/null 2>&1 || true
  docker volume rm "${VOLUME_NAME}" >/dev/null 2>&1 || true
fi

# The previous version always did `docker rm -f` + a fresh `docker run`
# here, which wiped the container's entire filesystem on every retry -
# including apt-installed packages and, before named volumes existed, the
# multi-GB Denodo downloads. If a container from a previous attempt already
# exists, resume *that* container instead: `docker start` keeps everything
# it had (downloaded files, installed packages, partial progress), and
# entrypoint.sh + linux/install.sh's own idempotency checks pick up wherever
# they left off.
if docker inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
  echo "Found an existing '${IMAGE_NAME}' container - resuming it instead of rebuilding, so any"
  echo "partially completed install work isn't thrown away."
  echo "(Env vars like --DENODO_UPDATE can't be changed on a resumed container - remove it first"
  echo "if you need to change them; see the from-scratch command below.)"
  docker start "${IMAGE_NAME}" >/dev/null
else
  echo "No existing container found - building the image and creating a new one."

  # Rollback safety: keep the previous image under a ':previous' tag instead
  # of letting a new build silently replace it.
  if docker image inspect "${IMAGE_NAME}:${IMAGE_TAG}" >/dev/null 2>&1; then
    echo "Tagging existing ${IMAGE_NAME}:${IMAGE_TAG} as ${IMAGE_NAME}:previous for rollback."
    docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${IMAGE_NAME}:previous"
  fi

  docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" "${SCRIPT_DIR}/docker"

  # A named volume is a second safety net (on top of container reuse above):
  # it keeps the Denodo install/database intact even if this container is
  # later removed and recreated (e.g. after an image rebuild). Docker
  # creates it automatically on first use; entrypoint.sh symlinks the
  # various real paths (repo, /home/denodo, Denodo install, AI SDK,
  # Postgres) into subdirectories of it.
  docker run --name "${IMAGE_NAME}" -d \
    -p 80:80 \
    -v "${VOLUME_NAME}":/data \
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
fi

echo ""
echo "Container is running in the background. Once install completes, the app is at http://localhost"
echo "Following its logs now (Ctrl-C stops watching - the container keeps running):"
echo ""
docker logs -f "${IMAGE_NAME}"
echo ""
echo "From-scratch reinstall: re-run this script with --reset"
