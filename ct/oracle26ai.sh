#!/usr/bin/env bash
# Oracle AI Database 26ai — LXC Deployment Script
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/runionow/proxmox-oracle26ai/main/ct/oracle26ai.sh)
set -euo pipefail

# Source shared functions (local first, then curl from GitHub)
GITHUB_RAW="https://raw.githubusercontent.com/runionow/proxmox-oracle26ai/main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
if [[ -n "$SCRIPT_DIR" && -f "${SCRIPT_DIR}/../misc/build.func" ]]; then
  # shellcheck source=../misc/build.func
  source "${SCRIPT_DIR}/../misc/build.func"
else
  source <(curl -fsSL "${GITHUB_RAW}/misc/build.func") || {
    echo "ERROR: Failed to download shared functions from GitHub."
    echo "Check your internet connection or clone the repo locally."
    exit 1
  }
fi

# Pre-flight checks
check_root
check_proxmox
check_internet

# Load .env overrides
load_env

# ============================================================
# TUI FLOW (max 6 screens)
# ============================================================

# Screen 1: Welcome
whiptail_msg "Oracle AI Database 26ai" \
  "Welcome to the Oracle AI Database 26ai LXC Installer!\n\nThis will create a privileged LXC container with Docker and deploy Oracle AI Database 26ai Free.\n\nPress OK to continue." || { msg_warn "Installation cancelled."; exit 0; }

# Screen 2: Oracle Image Selection
ORACLE_IMAGE_TAG=$(whiptail_menu "Oracle Image" "Choose Oracle 26ai image flavor:" \
  "23.26.0.0"    "Full image (~10GB) — all features, recommended" ON \
  "latest-lite"  "Lite image (~2GB)  — faster download, dev use" OFF)
msg_ok "Selected image: container-registry.oracle.com/database/free:${ORACLE_IMAGE_TAG}"

# Screen 3: Resources (single form — CPU, RAM, Disk)
RESOURCES=$(whiptail --title "Resources" --form "Configure container resources:" 15 60 3 \
  "CPU Cores:"  1 1 "${CT_CORES:-4}"     1 14 10 4 \
  "RAM (MB):"   2 1 "${CT_MEMORY:-8192}" 2 14 10 6 \
  "Disk (GB):"  3 1 "${CT_DISK_SIZE:-32}" 3 14 10 4 \
  3>&1 1>&2 2>&3) || { msg_warn "Deployment cancelled."; exit 0; }
CT_CORES=$(echo "$RESOURCES" | sed -n '1p' | tr -d '[:space:]')
CT_MEMORY=$(echo "$RESOURCES" | sed -n '2p' | tr -d '[:space:]')
CT_DISK_SIZE=$(echo "$RESOURCES" | sed -n '3p' | tr -d '[:space:]')

# Screen 4: Network
NETWORK_TYPE=$(whiptail_menu "Network" "Choose networking:" \
  "dhcp"   "DHCP — automatic IP (recommended)" ON \
  "static" "Static IP — manual configuration" OFF)

if [[ "$NETWORK_TYPE" == "static" ]]; then
  # Screen 4b: Static IP configuration (single form)
  STATIC_CONFIG=$(whiptail --title "Static IP" --form "Configure static IP address:" 15 65 3 \
    "IP/CIDR (e.g. 192.168.1.100/24):" 1 1 "" 1 35 25 20 \
    "Gateway IP:"                       2 1 "" 2 35 25 15 \
    "DNS Server (blank=gateway):"       3 1 "" 3 35 25 15 \
    3>&1 1>&2 2>&3) || { msg_warn "Deployment cancelled."; exit 0; }
  CT_NETWORK=$(echo "$STATIC_CONFIG" | sed -n '1p' | tr -d '[:space:]')
  CT_GATEWAY=$(echo "$STATIC_CONFIG" | sed -n '2p' | tr -d '[:space:]')
  CT_DNS=$(echo "$STATIC_CONFIG" | sed -n '3p' | tr -d '[:space:]')
  CT_DNS="${CT_DNS:-$CT_GATEWAY}"
  NET_CONFIG="ip=${CT_NETWORK},gw=${CT_GATEWAY},nameserver=${CT_DNS}"
else
  NET_CONFIG="ip=dhcp"
fi

# Screen 5: Oracle Password
ORACLE_PWD=$(whiptail_input "Oracle Password" "Set Oracle SYS/SYSTEM password (min 8 chars):" "${ORACLE_PWD:-ChangeMe123!}")

# Screen 6: Confirmation
SUMMARY="Deployment Summary:\n\n"
SUMMARY+="  Image:    container-registry.oracle.com/database/free:${ORACLE_IMAGE_TAG}\n"
SUMMARY+="  CPU:      ${CT_CORES} cores\n"
SUMMARY+="  RAM:      ${CT_MEMORY} MB\n"
SUMMARY+="  Disk:     ${CT_DISK_SIZE} GB\n"
SUMMARY+="  Network:  ${NET_CONFIG}\n"
SUMMARY+="  Hostname: ${CT_HOSTNAME:-oracle26ai}\n\n"
SUMMARY+="Proceed with deployment?"

whiptail_yesno "Confirm Deployment" "$SUMMARY" || { msg_warn "Deployment cancelled."; exit 0; }

# ============================================================
# DEPLOYMENT
# ============================================================

# Get next available VMID
if [[ "${CT_ID:-auto}" == "auto" ]]; then
  VMID=$(next_vmid)
else
  VMID="${CT_ID}"
fi
check_vmid_available "$VMID"

# Detect storage if not configured
STORAGE="${CT_STORAGE:-}"
if [[ -z "$STORAGE" ]]; then
  STORAGE=$(detect_storage | head -1)
  [[ -z "$STORAGE" ]] && STORAGE="local-lvm"
fi

# Check disk space (Oracle full image + data = ~45GB minimum)
check_storage_space "${CT_DISK_SIZE}" "/"

# Set up cleanup trap
trap 'cleanup_on_error "${VMID:-}" "lxc"' ERR

# Download Debian 12 LXC template
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
msg_info "Checking for Debian 12 LXC template..."
if ! pveam list local 2>/dev/null | grep -q "$TEMPLATE"; then
  msg_info "Downloading Debian 12 template (one-time download)..."
  pveam download local "$TEMPLATE" || \
    pveam download local "debian-12-standard_12.2-1_amd64.tar.zst" || \
    msg_error "Failed to download Debian 12 template. Check: pveam update && pveam available --section system"
fi
msg_ok "Debian 12 template ready"

# Create LXC container
HOSTNAME="${CT_HOSTNAME:-oracle26ai}"
BRIDGE="${CT_BRIDGE:-vmbr0}"

msg_info "Creating LXC container (VMID: ${VMID})..."
pct create "${VMID}" \
  "local:vztmpl/${TEMPLATE}" \
  --hostname "${HOSTNAME}" \
  --cores "${CT_CORES:-4}" \
  --memory "${CT_MEMORY:-8192}" \
  --rootfs "${STORAGE}:${CT_DISK_SIZE:-32}" \
  --features "nesting=1,keyctl=1" \
  --unprivileged 0 \
  --net0 "name=eth0,bridge=${BRIDGE},${NET_CONFIG}" \
  --onboot 1 \
  --start 0
msg_ok "LXC container created (VMID: ${VMID})"

# Start container
msg_info "Starting LXC container..."
pct start "${VMID}"
sleep 5
msg_ok "Container started"

# Wait for network
msg_info "Waiting for network connectivity..."
attempt=0
while ! pct exec "${VMID}" -- ping -c1 -W3 8.8.8.8 &>/dev/null; do
  sleep 3
  ((attempt++))
  [[ $attempt -gt 10 ]] && msg_error "Container network not available after 30s. Check network config."
done
msg_ok "Container network ready"

# Push and execute install script
msg_info "Pushing install script to container..."
pct push "${VMID}" install/oracle26ai-install.sh /root/oracle26ai-install.sh --perms 0755

# Export variables for install script
pct exec "${VMID}" -- bash -c "
export ORACLE_IMAGE_TAG='${ORACLE_IMAGE_TAG}'
export ORACLE_PWD='${ORACLE_PWD}'
export ORACLE_CONTAINER_NAME='${ORACLE_CONTAINER_NAME:-oracle-26ai}'
export ORACLE_LISTENER_PORT='${ORACLE_LISTENER_PORT:-1521}'
bash /root/oracle26ai-install.sh
"

# Get container IP
CONTAINER_IP=$(pct exec "${VMID}" -- hostname -I | awk '{print $1}')

# Success summary
echo ""
msg_ok "======================================================="
msg_ok "Oracle AI Database 26ai is ready!"
msg_ok "======================================================="
echo ""
echo "  Container ID:     ${VMID}"
echo "  Hostname:         ${HOSTNAME}"
echo "  IP Address:       ${CONTAINER_IP}"
echo ""
echo "  Connection String: ${CONTAINER_IP}:1521/FREEPDB1"
echo "  SYS password:      (as configured)"
echo ""
echo "  Optional add-ons:"
echo "    APEX + ORDS:     bash scripts/setup-apex-ords.sh"
echo "    Vector Demo:     bash scripts/setup-vector-demo.sh"
echo "    Backup/Restore:  bash scripts/backup.sh"
echo "    SSL/TLS:         bash scripts/setup-ssl.sh"
echo ""
