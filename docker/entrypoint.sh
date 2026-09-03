#!/bin/bash
## Entrypoint for the denodo-oneclick Docker image.
## Confirms the container received its configuration correctly; does not
## install or run Denodo VDP yet.

echo "Hello World from Denodo one-click installer!"
echo ""
echo "Configuration received by the container:"
echo "  DENODO_SUPPORT_CI      = ${DENODO_SUPPORT_CI:-<unset>}"
echo "  DENODO_SUPPORT_SECRET  = ${DENODO_SUPPORT_SECRET:+<set>}"
echo "  DENODO_LIC             = $( [ -f /denodo/license.lic ] && echo 'mounted at /denodo/license.lic' || echo '<missing>')"
echo "  DENODO_UPDATE          = ${DENODO_UPDATE:-<unset>}"
echo "  DENODO_PG_USER         = ${DENODO_PG_USER:-<unset>}"
echo "  DENODO_PG_PWD          = ${DENODO_PG_PWD:+<set>}"
echo "  DENODO_VDP_USER        = ${DENODO_VDP_USER:-<unset>}"
echo "  DENODO_VDP_PWD         = ${DENODO_VDP_PWD:+<set>}"
echo "  CLOUDFLARE_TUNNEL_KEY  = ${CLOUDFLARE_TUNNEL_KEY:+<set>}"


## Single persistent volume: install.sh mounts one named volume at /data
## instead of one volume per directory. Everything that needs to survive a
## container recreation is symlinked into a subdirectory of /data instead.
DATA_ROOT="/data"
mkdir -p "$DATA_ROOT"

link_to_data() {
  local real_path="$1" data_subdir="$2" owner="${3:-}"
  local data_path="$DATA_ROOT/$data_subdir"
  mkdir -p "$data_path"

  if [ -L "$real_path" ]; then
    return 0 # already linked on a previous boot
  fi

  if [ -e "$real_path" ]; then
    # First boot with something already at this path (e.g. useradd -m's
    # skeleton files under /home/denodo) - move it into the volume once so
    # nothing is silently lost, then replace the real path with a symlink.
    if [ -z "$(ls -A "$data_path" 2>/dev/null)" ]; then
      (shopt -s dotglob; mv "$real_path"/* "$data_path"/ 2>/dev/null || true)
    fi
    rm -rf "$real_path"
  fi

  ln -sfn "$data_path" "$real_path"
  [ -n "$owner" ] && chown "$owner" "$data_path"
}

# postgres's own ownership isn't set here - the apt-installed package
# manages that itself during initdb, same as before this existed.
# No separate link for the AI SDK: it now lives at /opt/denodo/denodo-aisdk,
# already covered by the /opt/denodo link below.
link_to_data /opt/denodo-oneclick repo denodo:denodo
link_to_data /home/denodo home denodo:denodo
link_to_data /opt/denodo denodo denodo:denodo
link_to_data /var/lib/postgresql postgres

## Marker set once a full install has completed successfully (see below).
## Persisted in /data itself (not one of the symlinked subdirs), so it
## survives container recreation as long as the volume does.
INSTALL_MARKER="$DATA_ROOT/.denodo_install_complete"

## Installing dependencies inthe container
LOG="/var/log/denodo-entrypoint.log"
touch "$LOG"

echo "[INIT] Installing dependencies..." | tee -a $LOG
sudo apt update
sudo apt install git unzip -y

# Seen consistently (not just intermittently) on some networks: git's
# smart-HTTP client over HTTP/2 gets a truncated response - reported as
# "could not read Username" / "expected flush after ref listing" - which is
# actually an MTU mismatch on the container's network path (common with
# Docker Desktop behind a VPN/virtual adapter with a smaller MTU than
# Docker's default), not a real auth problem. Forcing HTTP/1.1 avoids
# HTTP/2's larger frames; the bigger buffer is a cheap second safeguard.
# --system (not --global) so this covers every clone in the container,
# regardless of which user runs it (root here, "denodo" later in
# linux/install.sh for the AI SDK clone).
sudo git config --system http.version HTTP/1.1
sudo git config --system http.postBuffer 157286400

# Install Denodo-Oneclick repository

# Defaults (in case .env is missing values)
GITHUB_REPO=${GITHUB_REPO:-"vfagesgo/denodo-oneclick"}
INSTALL_DIR="/opt/denodo-oneclick"
BRANCH=${BRANCH:-"main"}

GITHUB_REPO_URL="https://github.com/$GITHUB_REPO.git"

echo "[INIT] Repo: $GITHUB_REPO" | tee -a $LOG
echo "[INIT] Install dir: $INSTALL_DIR" | tee -a $LOG
echo "[INIT] Branch: $BRANCH" | tee -a $LOG
mkdir -p "$INSTALL_DIR"

# Clone or update repo
if [ ! -d "$INSTALL_DIR/.git" ]; then
  echo "[INIT] Cloning Denodo-Oneclick repository..." | tee -a $LOG
  echo "[INIT] GITHUB_REPO: $GITHUB_REPO" | tee -a $LOG
  echo "[INIT] GITHUB_REPO_URL: $GITHUB_REPO_URL" | tee -a $LOG
  git clone -b "$BRANCH" "$GITHUB_REPO_URL" "$INSTALL_DIR" | tee -a $LOG
  chown -R denodo:denodo "$INSTALL_DIR" | tee -a $LOG
  
else
  echo "[INIT] Updating repository (force reset)..." | tee -a $LOG
  cd "$INSTALL_DIR" || exit 1

  git fetch origin
  git reset --hard "origin/$BRANCH"
  git clean -fd
  # Unlike the first-clone branch above, this ran without re-chowning
  # afterward - files touched by `git reset`/`clean` here (run as root)
  # drifted back to root ownership on every restart. Harmless for this
  # script (root's own git calls are exempt from git's ownership check),
  # but broke `git` commands run directly as "denodo" later - e.g.
  # install.sh's --upgrade/--refresh, which exec into the container as
  # denodo and got "detected dubious ownership in repository".
  chown -R denodo:denodo "$INSTALL_DIR"
fi

# Belt-and-suspenders alongside the chown above: explicitly mark this repo
# (and everything under the persisted volume, since /opt/denodo-oneclick is
# itself a symlink into it) as safe for git run as "denodo", regardless of
# whatever UID actually owns it at any given moment.
if ! sudo -u denodo git config --global --get-all safe.directory 2>/dev/null | grep -qx '\*'; then
  sudo -u denodo git config --global --add safe.directory '*'
fi

# Example: run install script if exists
rc=1
if [ -f "$INSTALL_DIR/linux/install.sh" ]; then
  echo "[INIT] Running install.sh as Denodo" | tee -a $LOG
  chmod +x "$INSTALL_DIR/linux/install.sh" 

  echo "[INIT] whoami=$(whoami)" | tee -a $LOG
  echo "[INIT] denodo user:" | tee -a $LOG
  id denodo >> "$LOG" 2>&1
  ls -l "$INSTALL_DIR/linux/install.sh" >> $LOG 2>&1

  echo "denodo ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/denodo
  chmod 440 /etc/sudoers.d/denodo

  # Was fully redirected to $LOG before (invisible on `docker run` output,
  # and lost entirely once the --rm container exits). Tee it instead so the
  # real error is visible immediately, while still keeping the log copy.
  #
  # Fixes vs. earlier versions:
  # - Run linux/install.sh (the tested Raspberry Pi installer) instead of
  #   the repo's top-level install.sh (the Docker orchestrator itself,
  #   also present since the whole repo was cloned into $INSTALL_DIR).
  # - `sudo -u denodo` without -E/--preserve-env strips the DENODO_* vars
  #   that `docker run -e` set, so explicitly preserve the ones the
  #   installer reads.
  # - If a previous run already finished successfully (INSTALL_MARKER), skip
  #   straight to (re)starting services instead of redoing the whole install
  #   - but only if the OS-level install actually looks intact. The marker
  #   lives on the volume and can outlive a container recreation, while
  #   apt-installed packages/config under / do not, so trust it only when
  #   both agree.
  # DENODO_ACTION controls how much of linux/install.sh runs - see that
  # script for the full list ("install", "services-only", "refresh",
  # "upgrade"). This normal container-boot path only ever decides between
  # "install" (first time / OS looks reset) and "services-only" (repeat
  # start); "refresh" and "upgrade" are triggered separately on demand via
  # `docker exec`, not through this boot path - see the top-level
  # install.sh's --refresh/--upgrade flags.
  DENODO_ACTION="install"
  if [ -f "$INSTALL_MARKER" ] && command -v nginx >/dev/null 2>&1 && command -v pg_ctlcluster >/dev/null 2>&1; then
    echo "[INIT] Previous install marker found and OS packages look intact - services-only start" | tee -a "$LOG"
    DENODO_ACTION="services-only"
  fi
  export DENODO_ACTION

  set -o pipefail
  sudo -H -u denodo \
    --preserve-env=DENODO_SUPPORT_CI,DENODO_SUPPORT_SECRET,DENODO_LIC,DENODO_UPDATE,DENODO_PG_USER,DENODO_PG_PWD,DENODO_VDP_USER,DENODO_VDP_PWD,DENODO_ACTION \
    bash "$INSTALL_DIR/linux/install.sh" 2>&1 | tee -a "$LOG"
  rc=$?

  echo "[INIT] install.sh exit code=$rc" | tee -a "$LOG"

  if [ "$rc" -eq 0 ] && [ "$DENODO_ACTION" = "install" ]; then
    echo "[INIT] Full install succeeded - writing $INSTALL_MARKER so future starts skip straight to services" | tee -a "$LOG"
    date -u +%Y-%m-%dT%H:%M:%SZ > "$INSTALL_MARKER"
  fi

fi

# If the install failed (or linux/install.sh wasn't even found), the
# container must actually exit here. install.sh on the host resumes a
# stopped container with `docker start` rather than recreating it, so
# staying "up" despite a failure would make that resume a no-op and the
# install would never actually retry.
if [ "$rc" -ne 0 ]; then
  echo "[INIT] Install did not complete successfully (exit $rc) - exiting so the next 'docker start' retries it" | tee -a "$LOG"
  exit "$rc"
fi

echo "[INIT] Completed" | tee -a $LOG
echo "[INIT] Install succeeded - keeping the container up (nginx should be serving on port 80)" | tee -a "$LOG"

# Keep the container's main process alive so it stays up once the install
# succeeds. `-F` (not `-f`) keeps following across log rotation/truncation.
exec tail -F "$LOG" /var/log/1-denodo_install.log 2>/dev/null

