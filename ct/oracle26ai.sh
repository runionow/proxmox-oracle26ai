#!/usr/bin/env bash
# Oracle AI Database 26ai — LXC Deployment Script
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/runionow/proxmox-oracle26ai/main/ct/oracle26ai.sh)
set -euo pipefail

# Ensure terminal is properly configured for interactive prompts
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
# USER PROMPTS (simple read — works in any terminal)
# ============================================================

echo ""
echo "============================================="
echo "  Oracle AI Database 26ai — LXC Installer"
echo "============================================="
echo "Press ENTER to accept default values [shown in brackets]"
echo ""

# Image selection
log "Prompting for image selection"
echo "Oracle image options:"
echo "  1) Full image (~10GB, all features) [recommended]"
echo "  2) Lite image (~2GB, faster download, dev use)"
read -r -p "Choose image [1]: " _IMG_CHOICE
_IMG_CHOICE="${_IMG_CHOICE:-1}"
if [[ "$_IMG_CHOICE" == "2" || "$_IMG_CHOICE" == "lite" ]]; then
  ORACLE_IMAGE_TAG="latest-lite"
else
  ORACLE_IMAGE_TAG="${ORACLE_IMAGE_TAG:-23.26.0.0}"
fi
log "Image selected: ${ORACLE_IMAGE_TAG}"
echo "  → Image: container-registry.oracle.com/database/free:${ORACLE_IMAGE_TAG}"
echo ""

# Resources
log "Prompting for resources"
read -r -p "CPU cores [${CT_CORES:-4}]: " _INPUT
CT_CORES="${_INPUT:-${CT_CORES:-4}}"
log "CT_CORES=${CT_CORES}"

read -r -p "RAM in MB [${CT_MEMORY:-8192}]: " _INPUT
CT_MEMORY="${_INPUT:-${CT_MEMORY:-8192}}"
log "CT_MEMORY=${CT_MEMORY}"

read -r -p "Disk size in GB [${CT_DISK_SIZE:-32}]: " _INPUT
CT_DISK_SIZE="${_INPUT:-${CT_DISK_SIZE:-32}}"
log "CT_DISK_SIZE=${CT_DISK_SIZE}"
echo ""

# Network
log "Prompting for network configuration"
echo "Network options:"
echo "  1) DHCP — automatic IP [recommended]"
echo "  2) Static IP — manual configuration"
read -r -p "Choose network [1]: " _NET_CHOICE
_NET_CHOICE="${_NET_CHOICE:-1}"
if [[ "$_NET_CHOICE" == "2" || "$_NET_CHOICE" == "static" ]]; then
  log "Static IP selected"
  read -r -p "IP address with CIDR (e.g 192.168.1.100/24): " _CT_NETWORK
  read -r -p "Gateway IP: " _CT_GATEWAY
  read -r -p "DNS server [leave empty = use gateway]: " _CT_DNS
  CT_DNS="${_CT_DNS:-$_CT_GATEWAY}"
  NET_CONFIG="ip=${_CT_NETWORK},gw=${_CT_GATEWAY},nameserver=${CT_DNS}"
  log "Static IP configured: ${NET_CONFIG}"
else
  NET_CONFIG="ip=dhcp"
  log "DHCP selected"
fi
echo ""

# Password
log "Prompting for Oracle password"
read -r -p "Oracle SYS password [ChangeMe123!]: " _INPUT
ORACLE_PWD="${_INPUT:-${ORACLE_PWD:-ChangeMe123!}}"
log "Oracle password set"
echo ""

# Confirmation
log "Showing deployment summary"
echo "============================================="
echo "  Deployment Summary"
echo "============================================="
echo "  Image:    container-registry.oracle.com/database/free:${ORACLE_IMAGE_TAG}"
echo "  CPU:      ${CT_CORES} cores"
echo "  RAM:      ${CT_MEMORY} MB"
echo "  Disk:     ${CT_DISK_SIZE} GB"
echo "  Network:  ${NET_CONFIG}"
echo "  Hostname: ${CT_HOSTNAME:-oracle26ai}"
echo "============================================="
echo ""
read -r -p "Proceed with deployment? [y/N]: " _CONFIRM
if [[ "${_CONFIRM,,}" != "y" && "${_CONFIRM,,}" != "yes" ]]; then
  log "Deployment cancelled by user"
  msg_warn "Deployment cancelled."
  exit 0
fi
log "Deployment confirmed"

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
