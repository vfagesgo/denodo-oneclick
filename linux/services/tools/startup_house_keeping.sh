#!/usr/bin/env bash
set -euo pipefail

# This script is meant to run once during boot from a systemd unit.
# It cleans previous logs to avoid to run out of disk space
# If you want to disable this script remove the denodo_house_keeping.service file from the services folder
LOG=/var/log/0-Pre_boot_update.log
sudo touch "$LOG"

log_section() {
  echo "[SECTION $1] $2" | tee -a "$LOG"
}

log_step() {
  echo "[STEP] $1" | tee -a "$LOG"
}

clean_logs(){
  log_section "1" "Remove system log"
  log_step "Delete /opt/denodo-9/logs/*/*.log"
  sudo find /opt/denodo-9/logs -mindepth 2 -maxdepth 2 -type f -name "*.log" -delete
  log_step "Delete .log files under /var/log except $LOG"
  sudo find /var/log -type f -name "*.log" ! -path "$LOG" -delete
}

main() {
  # Load environment variables from the boot partition when available.
  if [ -f /boot/firmware/denodo/denodo_config.env ]; then
      log_step "Loading config from /boot/firmware/denodo/denodo_config.env"
      set -o allexport
      source /boot/firmware/denodo/denodo_config.env
      set +o allexport
  else
      log_step "No config file found; continuing with defaults"
  fi

  ## First delete logs to avoid disk over usage
  clean_logs
  
}

main "$@"
