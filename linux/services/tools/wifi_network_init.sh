#!/usr/bin/env bash
set -euo pipefail

# This script is meant to run once during boot from a systemd unit.
# It reads the cloud-init style boot network file, extracts the first Wi-Fi
# definition, and rewrites wpa_supplicant so the device joins that network.

LOG=/var/log/2-wifi_network_init.log

NETWORK_CONFIG_CANDIDATES=(
  "/boot/firmware/network-config"
  "/boot/network-config"
)

log_section() {
  echo "[SECTION $1] $2" | tee -a "$LOG"
}

log_step() {
  echo "[STEP] $1" | tee -a "$LOG"
}

configure_hostname() {
  if [ -z "${HOSTNAME:-}" ]; then
    log_step "HOSTNAME not provided; keeping current hostname"
    return 0
  fi

  log_step "Setting system hostname to '$HOSTNAME'"
  sudo hostnamectl set-hostname "$HOSTNAME"

  if command -v nmcli >/dev/null 2>&1; then
    log_step "Setting NetworkManager hostname to '$HOSTNAME'"
    sudo nmcli general hostname "$HOSTNAME"
  else
    log_step "nmcli not available; skipped NetworkManager hostname update"
  fi
}

find_network_config() {
  local candidate
  for candidate in "${NETWORK_CONFIG_CANDIDATES[@]}"; do
    if [ -f "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

extract_first_ssid() {
  awk '
    /access-points:/ { in_ap=1; next }
    in_ap && $0 ~ /^[[:space:]]*"/ {
      line=$0
      sub(/^[[:space:]]*"/, "", line)
      sub(/":[[:space:]]*$/, "", line)
      print line
      exit
    }
  ' "$1"
}

extract_password_for_ssid() {
  awk -v target_ssid="$2" '
    $0 ~ /^[[:space:]]*"/ {
      current_ssid=$0
      sub(/^[[:space:]]*"/, "", current_ssid)
      sub(/":[[:space:]]*$/, "", current_ssid)
      next
    }
    current_ssid == target_ssid && $0 ~ /^[[:space:]]*password:[[:space:]]*"/ {
      password=$0
      sub(/^[[:space:]]*password:[[:space:]]*"/, "", password)
      sub(/"[[:space:]]*$/, "", password)
      print password
      exit
    }
  ' "$1"
}

extract_country() {
  awk '
    $0 ~ /^[[:space:]]*regulatory-domain:[[:space:]]*"/ {
      country=$0
      sub(/^[[:space:]]*regulatory-domain:[[:space:]]*"/, "", country)
      sub(/"[[:space:]]*$/, "", country)
      print country
      exit
    }
  ' "$1"
}

main() {
  touch "$LOG"


  # Load environment variables from the boot partition when available.
  log_section "1" "Load env variables"
  if [ -f /boot/firmware/denodo/denodo_config.env ]; then
      log_step "Loading config from /boot/firmware/denodo/denodo_config.env"
      set -o allexport
      source /boot/firmware/denodo/denodo_config.env
      set +o allexport
  else
      log_step "No config file found; continuing with defaults"
  fi

  log_section "2" "Configure Hostname"
  configure_hostname

  log_section "3" "Network Configuration"
  local network_config
  network_config=$(find_network_config || true)
  if [ -z "${network_config:-}" ]; then
    log_step "No boot network-config file found; nothing to apply"
    exit 0
  fi

  log_step "Using network config: $network_config"

  local ssid
  ssid=$(extract_first_ssid "$network_config")
  if [ -z "${ssid:-}" ]; then
    log_step "No Wi-Fi SSID found in $network_config"
    exit 0
  fi

  local password
  password=$(extract_password_for_ssid "$network_config" "$ssid")
  if [ -z "${password:-}" ]; then
    log_step "No password found for SSID '$ssid' in $network_config"
    exit 1
  fi

  log_step "Wifi password found for SSID '$ssid' in $password"

  local country
  country=$(extract_country "$network_config")
  country=${country:-FR}

  log_step "Applying Wi-Fi configuration for SSID '$ssid' with country '$country'"

  local tmp_conf
  local psk_line
  tmp_conf=$(mktemp)


  # Wait until the SSID becomes visible
  for i in {1..30}; do
      if nmcli -t -f SSID device wifi list | grep -Fxq "$ssid"; then
          log_step "[WIFI-INIT] Found SSID '$ssid'"
          break
      fi

      log_step "[WIFI-INIT] Waiting for SSID '$ssid'..."
      sleep 2
  done

  sudo nmcli connection delete "$ssid" || true
  sudo nmcli device wifi connect "$ssid" password "$password"
  log_step "Wi-Fi configuration applied successfully"


  ## Start CLoudflare tunnel if a cloudflare CLOUDFLARE_TUNNEL_KEY is define

  UNIT_FILE="/etc/systemd/system/cloudflared.service"

  log_section "4" "Configure Cloudflare Tunnel"
  if [ -z "${CLOUDFLARE_TUNNEL_KEY:-}" ]; then
    log_step "No CLOUDFLARE_TUNNEL_KEY → disabling cloudflared"

    sudo systemctl stop cloudflared || true
    sudo systemctl disable cloudflared || true

    log_step "cloudflared disabled"
  else
    log_step "Updating Cloudflare token in systemd unit"

    sudo systemctl stop cloudflared || true

    #sudo sed -i "s|--token .*|--token ${CLOUDFLARE_TUNNEL_KEY}|" "$UNIT_FILE"
    #sudo systemctl daemon-reload
    #sudo systemctl enable cloudflared || true
    #sudo systemctl restart cloudflared || true

    sudo /usr/bin/cloudflared --no-autoupdate tunnel run --token $CLOUDFLARE_TUNNEL_KEY & 

    log_step "cloudflared restarted with new token"
  fi


}

main "$@"
