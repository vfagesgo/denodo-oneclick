#!/bin/sh
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


## Installing dependencies inthe container
LOG="/var/log/denodo-entrypoint.log"
touch "$LOG"

echo "[INIT] Installing dependencies..." | tee -a $LOG
sudo apt update
sudo apt install git unzip -y

# Install Denodo-Oneclick repository

# Defaults (in case .env is missing values)
GITHUB_REPO=${GITHUB_REPO:-"vfagesgo/denodo-oneclick"}
INSTALL_DIR="/opt/denodo"
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
fi

# Example: run install script if exists
if [ -f "$INSTALL_DIR/linux/install.sh" ]; then
  echo "[INIT] Running install.sh as Denodo" | tee -a $LOG
  chmod +x "$INSTALL_DIR/linux/install.sh" 

  echo "[INIT] whoami=$(whoami)" | tee -a $LOG
  echo "[INIT] denodo user:" | tee -a $LOG
  id denodo >> "$LOG" 2>&1
  ls -l "$INSTALL_DIR/linux/install.sh" >> $LOG 2>&1

  echo "denodo ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/denodo
  chmod 440 /etc/sudoers.d/denodo

  sudo -H -u denodo bash "$INSTALL_DIR/install.sh" >> $LOG 2>&1
  
  rc=$?

  echo "[INIT] install.sh exit code=$rc" | tee -a "$LOG"

fi

echo "[INIT] Completed" | tee -a $LOG

