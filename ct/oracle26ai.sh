#!/usr/bin/env bash
# Oracle AI Database 26ai — LXC Deployment Script
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/runionow/proxmox-oracle26ai/main/ct/oracle26ai.sh)
set -euo pipefail

# Ensure whiptail works over SSH (TERM=dumb breaks TUI)
[[ "${TERM:-}" == "dumb" || -z "${TERM:-}" ]] && export TERM="xterm-256color"

# Debug logging (enabled by default, check /tmp/oracle26ai-debug.log)
DEBUGLOG="/tmp/oracle26ai-debug.log"
log() { echo "[$(date '+%H:%M:%S')] $*" >> "$DEBUGLOG"; }
log "=== Oracle 26ai LXC installer started ==="
log "TERM=$TERM, tty=$(tty 2>&1), stdin_isatty=$([ -t 0 ] && echo yes || echo no)"
echo "Debug log: $DEBUGLOG"

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
log "build.func loaded OK"

# Pre-flight checks
check_root
log "check_root passed"
check_proxmox
log "check_proxmox passed"
check_internet
log "check_internet passed"

# Load .env overrides
load_env
log "load_env done, ORACLE_IMAGE_TAG=${ORACLE_IMAGE_TAG}"

# ============================================================
# TUI FLOW (max 6 screens)
# ============================================================

# Screen 1: Welcome
log "About to show Screen 1 (Welcome)"
whiptail_msg "Oracle AI Database 26ai" \
  "Welcome to the Oracle AI Database 26ai LXC Installer!\n\nThis will create a privileged LXC container with Docker and deploy Oracle AI Database 26ai Free.\n\nPress OK to continue." || { msg_warn "Installation cancelled."; exit 0; }
log "Screen 1 passed"

# Screen 2: Oracle Image Selection
log "About to show Screen 2 (Image selection)"
ORACLE_IMAGE_TAG=$(whiptail_menu "Oracle Image" "Choose Oracle 26ai image flavor:" \
  "23.26.0.0"    "Full image (~10GB) — all features, recommended" ON \
  "latest-lite"  "Lite image (~2GB)  — faster download, dev use" OFF)
log "Screen 2 passed, ORACLE_IMAGE_TAG=${ORACLE_IMAGE_TAG}"
msg_ok "Selected image: container-registry.oracle.com/database/free:${ORACLE_IMAGE_TAG}"

# Screen 3: Resources
log "About to show Screen 3 (CPU)"
CT_CORES=$(whiptail_input "Resources — CPU" "Number of CPU cores:" "${CT_CORES:-4}")
log "Screen 3 passed, CT_CORES=${CT_CORES}"
CT_MEMORY=$(whiptail_input "Resources — RAM" "RAM in MB (min 4096, recommended 8192):" "${CT_MEMORY:-8192}")
log "RAM input done, CT_MEMORY=${CT_MEMORY}"
CT_DISK_SIZE=$(whiptail_input "Resources — Disk" "Disk size in GB (min 20, recommended 32+):" "${CT_DISK_SIZE:-32}")
log "Disk input done, CT_DISK_SIZE=${CT_DISK_SIZE}"

# Screen 4: Network
log "About to show Screen 4 (Network)"
NETWORK_TYPE=$(whiptail_menu "Network" "Choose networking:" \
  "dhcp"   "DHCP — automatic IP (recommended)" ON \
  "static" "Static IP — manual configuration" OFF)
log "Screen 4 passed, NETWORK_TYPE=${NETWORK_TYPE}"

if [[ "$NETWORK_TYPE" == "static" ]]; then
  log "Static IP selected, prompting for details"
  CT_NETWORK=$(whiptail_input "Static IP" "Enter IP address with CIDR (e.g. 192.168.1.100/24):" "")
  CT_GATEWAY=$(whiptail_input "Static IP" "Enter gateway IP:" "")
  CT_DNS=$(whiptail_input "Static IP" "Enter DNS server (or leave empty for gateway):" "")
  CT_DNS="${CT_DNS:-$CT_GATEWAY}"
  NET_CONFIG="ip=${CT_NETWORK},gw=${CT_GATEWAY},nameserver=${CT_DNS}"
  log "Static IP configured: ${NET_CONFIG}"
else
  NET_CONFIG="ip=dhcp"
  log "DHCP selected"
fi

# Screen 5: Oracle Password
log "About to show Screen 5 (Oracle Password)"
ORACLE_PWD=$(whiptail_input "Oracle Password" "Set Oracle SYS/SYSTEM password (min 8 chars):" "${ORACLE_PWD:-ChangeMe123!}")
log "Screen 5 passed, password set"

# Screen 6: Confirmation
log "About to show Screen 6 (Confirmation)"
SUMMARY="Deployment Summary:\n\n"
SUMMARY+="  Image:    container-registry.oracle.com/database/free:${ORACLE_IMAGE_TAG}\n"
SUMMARY+="  CPU:      ${CT_CORES} cores\n"
SUMMARY+="  RAM:      ${CT_MEMORY} MB\n"
SUMMARY+="  Disk:     ${CT_DISK_SIZE} GB\n"
SUMMARY+="  Network:  ${NET_CONFIG}\n"
SUMMARY+="  Hostname: ${CT_HOSTNAME:-oracle26ai}\n\n"
SUMMARY+="Proceed with deployment?"

whiptail_yesno "Confirm Deployment" "$SUMMARY" || { msg_warn "Deployment cancelled."; exit 0; }
log "Screen 6 passed, deployment confirmed"

# ============================================================
# DEPLOYMENT
# ============================================================
log "Starting deployment phase"

# Get next available VMID
if [[ "${CT_ID:-auto}" == "auto" ]]; then
  VMID=$(next_vmid)
else
  VMID="${CT_ID}"
fi
log "VMID assigned: ${VMID}"
check_vmid_available "$VMID"
log "VMID availability check passed"

# Detect storage if not configured
STORAGE="${CT_STORAGE:-}"
if [[ -z "$STORAGE" ]]; then
  STORAGE=$(detect_storage | head -1)
  [[ -z "$STORAGE" ]] && STORAGE="local-lvm"
fi
log "Storage pool: ${STORAGE}"

# Check disk space (Oracle full image + data = ~45GB minimum)
check_storage_space "${CT_DISK_SIZE}" "/"
log "Disk space check passed"

# Set up cleanup trap
trap 'cleanup_on_error "${VMID:-}" "lxc"' ERR
log "Cleanup trap set"

# Download Debian 12 LXC template
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
log "Checking for Debian 12 LXC template"
msg_info "Checking for Debian 12 LXC template..."
if ! pveam list local 2>/dev/null | grep -q "$TEMPLATE"; then
  log "Template not found, downloading..."
  msg_info "Downloading Debian 12 template (one-time download)..."
  pveam download local "$TEMPLATE" || \
    pveam download local "debian-12-standard_12.2-1_amd64.tar.zst" || \
    msg_error "Failed to download Debian 12 template. Check: pveam update && pveam available --section system"
fi
log "Debian 12 template ready"
msg_ok "Debian 12 template ready"

# Create LXC container
HOSTNAME="${CT_HOSTNAME:-oracle26ai}"
BRIDGE="${CT_BRIDGE:-vmbr0}"

log "Creating LXC container VMID=${VMID}, hostname=${HOSTNAME}"
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
log "LXC container created successfully"
msg_ok "LXC container created (VMID: ${VMID})"

# Start container
log "Starting LXC container"
msg_info "Starting LXC container..."
pct start "${VMID}"
sleep 5
log "Container started, waiting for boot"
msg_ok "Container started"

# Wait for network
log "Waiting for network connectivity"
msg_info "Waiting for network connectivity..."
attempt=0
while ! pct exec "${VMID}" -- ping -c1 -W3 8.8.8.8 &>/dev/null; do
  sleep 3
  ((attempt++))
  [[ $attempt -gt 10 ]] && msg_error "Container network not available after 30s. Check network config."
done
log "Container network ready"
msg_ok "Container network ready"

# Download and push install script to container
log "Downloading install script"
msg_info "Downloading install script..."
INSTALL_SCRIPT=""
if [[ -n "$SCRIPT_DIR" && -f "${SCRIPT_DIR}/../install/oracle26ai-install.sh" ]]; then
  INSTALL_SCRIPT="${SCRIPT_DIR}/../install/oracle26ai-install.sh"
else
  curl -fsSL "${GITHUB_RAW}/install/oracle26ai-install.sh" -o /tmp/oracle26ai-install.sh || \
    msg_error "Failed to download install script from GitHub."
  INSTALL_SCRIPT="/tmp/oracle26ai-install.sh"
fi
log "Install script ready: ${INSTALL_SCRIPT}"

log "Pushing install script to container"
msg_info "Pushing install script to container..."
pct push "${VMID}" "${INSTALL_SCRIPT}" /root/oracle26ai-install.sh --perms 0755
log "Install script pushed"

# Export variables and run install script
log "Running install script in container"
pct exec "${VMID}" -- bash -c "
export ORACLE_IMAGE_TAG='${ORACLE_IMAGE_TAG}'
export ORACLE_PWD='${ORACLE_PWD}'
export ORACLE_CONTAINER_NAME='${ORACLE_CONTAINER_NAME:-oracle-26ai}'
export ORACLE_LISTENER_PORT='${ORACLE_LISTENER_PORT:-1521}'
bash /root/oracle26ai-install.sh
"
log "Install script completed"

# Get container IP
log "Retrieving container IP"
CONTAINER_IP=$(pct exec "${VMID}" -- hostname -I | awk '{print $1}')
log "Container IP: ${CONTAINER_IP}"

# Success summary
log "=== Oracle 26ai LXC installer completed successfully ==="
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
