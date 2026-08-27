#!/usr/bin/env bash
set -euo pipefail

# This script overwrite the applications config files
# by replacing them with the file provided under /boot/firmware/denodo folder

LOG=/var/log/0-Pre_boot_update.log
sudo touch $LOG

log_section() {
  echo "[SECTION $1] $2" | tee -a "$LOG"
}

log_step() {
  echo "[STEP] $1" | tee -a "$LOG"
}

main() {
  log_section "2" "Update config files"

  # Load environment variables from the boot partition when available.
  if [ -f /boot/firmware/denodo/denodo_config.env ]; then
      log_step "Loading config from /boot/firmware/denodo/denodo_config.env"
      set -o allexport
      source /boot/firmware/denodo/denodo_config.env
      set +o allexport
  else
      log_step "No config file found; continuing with defaults"
  fi

  # Copy Denodo License File
  if [ -f /boot/firmware/denodo/$DENODO_LIC ]; then
    log_step "Copy Denodo license $DENODO_LIC"
    sudo cp "/boot/firmware/denodo/$DENODO_LIC" "/opt/denodo-9/conf/denodo.lic"
    sudo chown denodo:denodo "/opt/denodo-9/conf/denodo.lic"
  else 
    sudo rm /opt/denodo-9/conf/denodo.lic
  fi

  # Copy AISDK config File
  if [ -f /boot/firmware/denodo/sdk_config.env ]; then
    log_step "Update Denodo AISDK config file"
    sudo cp "/boot/firmware/denodo/sdk_config.env" "/opt/denodo-aisdk/api/utils/sdk_config.env"
    sudo chown denodo:denodo "/opt/denodo-aisdk/api/utils/sdk_config.env"
  else
    sudo rm /opt/denodo-aisdk/api/utils/sdk_config.env
  fi

  # Copy Chatbot config File
  if [ -f /boot/firmware/denodo/chatbot_config.env ]; then
    log_step "Update Denodo chatbot config file"
    sudo cp "/boot/firmware/denodo/chatbot_config.env" "/opt/denodo-aisdk/sample_chatbot/chatbot_config.env"
    sudo chown denodo:denodo "/opt/denodo-aisdk/sample_chatbot/chatbot_config.env"
  else 
    sudo rm /opt/denodo-aisdk/sample_chatbot/chatbot_config.env
  fi

  
}

main "$@"
