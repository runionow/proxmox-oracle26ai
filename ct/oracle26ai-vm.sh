#!/usr/bin/env bash
# Oracle AI Database 26ai — KVM VM Deployment Script
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/YOURUSERNAME/proxmox-oracle26ai/main/ct/oracle26ai-vm.sh)
set -euo pipefail

# Source shared functions (local first, then curl from GitHub)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../misc/build.func" ]]; then
  # shellcheck source=../misc/build.func
  source "${SCRIPT_DIR}/../misc/build.func"
else
  source <(curl -fsSL https://raw.githubusercontent.com/YOURUSERNAME/proxmox-oracle26ai/main/misc/build.func)
fi

# Pre-flight checks
check_root
check_proxmox
check_internet
load_env

# ============================================================
# TUI FLOW (max 6 screens — mirrors LXC script)
# ============================================================

# Screen 1: Welcome
whiptail_msg "Oracle AI Database 26ai" \
  "Welcome to the Oracle AI Database 26ai VM Installer!\n\nThis will create a KVM virtual machine with Docker and deploy Oracle AI Database 26ai Free.\n\nPress OK to continue."

# Screen 2: Oracle Image Selection
ORACLE_IMAGE_TAG=$(whiptail_menu "Oracle Image" "Choose Oracle 26ai image flavor:" \
  "23.26.0.0"    "Full image (~10GB) — all features, recommended" ON \
  "latest-lite"  "Lite image (~2GB)  — faster download, dev use" OFF)
msg_ok "Selected image: container-registry.oracle.com/database/free:${ORACLE_IMAGE_TAG}"

# Screen 3: Resources (single form — CPU, RAM, Disk)
RESOURCES=$(whiptail --title "Resources" --form "Configure VM resources:" 15 60 3 \
  "CPU Cores:"  1 1 "${CT_CORES:-4}"     1 14 10 4 \
  "RAM (MB):"   2 1 "${CT_MEMORY:-8192}" 2 14 10 6 \
  "Disk (GB):"  3 1 "${CT_DISK_SIZE:-40}" 3 14 10 4 \
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
  IPCONFIG="ip=${CT_NETWORK},gw=${CT_GATEWAY}"
else
  IPCONFIG="ip=dhcp"
fi

# Screen 5: Passwords (single form)
PASSWORDS=$(whiptail --title "Passwords" --form "Set deployment passwords:" 12 65 2 \
  "Oracle SYS password:"  1 1 "${ORACLE_PWD:-ChangeMe123!}" 1 24 30 50 \
  "VM root password:"     2 1 "Proxmox123!"                 2 24 30 50 \
  3>&1 1>&2 2>&3) || { msg_warn "Deployment cancelled."; exit 0; }
ORACLE_PWD=$(echo "$PASSWORDS" | sed -n '1p')
ROOT_PASSWORD=$(echo "$PASSWORDS" | sed -n '2p')

# Screen 6: Confirmation
SUMMARY="Deployment Summary:\n\n"
SUMMARY+="  Type:     KVM Virtual Machine\n"
SUMMARY+="  Image:    container-registry.oracle.com/database/free:${ORACLE_IMAGE_TAG}\n"
SUMMARY+="  CPU:      ${CT_CORES} cores\n"
SUMMARY+="  RAM:      ${CT_MEMORY} MB\n"
SUMMARY+="  Disk:     ${CT_DISK_SIZE} GB\n"
SUMMARY+="  Network:  ${IPCONFIG}\n\n"
SUMMARY+="Proceed with deployment?"

whiptail_yesno "Confirm Deployment" "$SUMMARY" || { msg_warn "Deployment cancelled."; exit 0; }

# ============================================================
# DEPLOYMENT
# ============================================================

# Get next VMID
if [[ "${CT_ID:-auto}" == "auto" ]]; then
  VMID=$(next_vmid)
else
  VMID="${CT_ID}"
fi
check_vmid_available "$VMID"

STORAGE="${CT_STORAGE:-}"
[[ -z "$STORAGE" ]] && STORAGE=$(detect_storage | head -1)
[[ -z "$STORAGE" ]] && STORAGE="local-lvm"
BRIDGE="${CT_BRIDGE:-vmbr0}"
HOSTNAME="${CT_HOSTNAME:-oracle26ai}"

check_storage_space "${CT_DISK_SIZE}" "/"

# Set up cleanup trap
trap 'cleanup_on_error "${VMID:-}" "vm"' ERR

# Download Debian 12 cloud image
CLOUD_IMAGE="debian-12-genericcloud-amd64.qcow2"
CLOUD_IMAGE_URL="https://cloud.debian.org/images/cloud/bookworm/latest/${CLOUD_IMAGE}"
CLOUD_IMAGE_PATH="/tmp/${CLOUD_IMAGE}"

if [[ ! -f "$CLOUD_IMAGE_PATH" ]]; then
  msg_info "Downloading Debian 12 cloud image (one-time, ~300MB)..."
  curl -fsSL --progress-bar -o "$CLOUD_IMAGE_PATH" "$CLOUD_IMAGE_URL" || \
    msg_error "Failed to download Debian 12 cloud image from ${CLOUD_IMAGE_URL}"
fi
msg_ok "Debian 12 cloud image ready"

# Create VM
msg_info "Creating KVM VM (VMID: ${VMID})..."
qm create "${VMID}" \
  --name "${HOSTNAME}" \
  --cores "${CT_CORES:-4}" \
  --memory "${CT_MEMORY:-8192}" \
  --scsihw virtio-scsi-pci \
  --scsi0 "${STORAGE}:0,import-from=${CLOUD_IMAGE_PATH},size=${CT_DISK_SIZE}G" \
  --ide2 "${STORAGE}:cloudinit" \
  --boot order=scsi0 \
  --serial0 socket \
  --vga serial0 \
  --net0 "virtio,bridge=${BRIDGE}" \
  --agent enabled=1 \
  --ostype l26
msg_ok "VM created (VMID: ${VMID})"

# Configure cloud-init
msg_info "Configuring cloud-init..."
qm set "${VMID}" \
  --ciuser root \
  --cipassword "${ROOT_PASSWORD}" \
  --ipconfig0 "${IPCONFIG}" \
  --sshkeys "" 2>/dev/null || true
[[ -n "${CT_DNS:-}" ]] && qm set "${VMID}" --nameserver "${CT_DNS}"
msg_ok "Cloud-init configured"

# Resize disk
msg_info "Resizing disk to ${CT_DISK_SIZE}GB..."
qm disk resize "${VMID}" scsi0 "${CT_DISK_SIZE}G" 2>/dev/null || true
msg_ok "Disk resized"

# Start VM
msg_info "Starting VM..."
qm start "${VMID}"
msg_ok "VM started"

# Wait for VM to boot and get IP
msg_info "Waiting for VM to boot (this takes 60-90 seconds)..."
boot_timeout=120
elapsed=0
VM_IP=""
while [[ $elapsed -lt $boot_timeout ]]; do
  VM_IP=$(qm guest cmd "${VMID}" network-get-interfaces 2>/dev/null | \
    grep -o '"ip-address":"[0-9.]*"' | grep -v '"127\.' | head -1 | \
    grep -o '[0-9.]*') || true
  [[ -n "${VM_IP:-}" ]] && break
  sleep 5
  ((elapsed+=5))
  msg_info "Still booting... (${elapsed}s elapsed)"
done
[[ -z "${VM_IP:-}" ]] && VM_IP="<check-proxmox-ui>"
msg_ok "VM booted. IP: ${VM_IP}"

# Push install script and execute via SSH or qm guest exec
msg_info "Deploying Oracle 26ai inside VM..."

# Try qm guest exec first, fallback to SSH
if qm guest cmd "${VMID}" ping &>/dev/null 2>&1; then
  # Upload script content via qm agent
  INSTALL_CONTENT=$(cat install/oracle26ai-install.sh)
  qm guest exec "${VMID}" -- bash -c "cat > /root/oracle26ai-install.sh << 'SCRIPT'
${INSTALL_CONTENT}
SCRIPT
chmod +x /root/oracle26ai-install.sh"

  qm guest exec "${VMID}" -- bash -c "
export ORACLE_IMAGE_TAG='${ORACLE_IMAGE_TAG}'
export ORACLE_PWD='${ORACLE_PWD}'
export ORACLE_CONTAINER_NAME='${ORACLE_CONTAINER_NAME:-oracle-26ai}'
export ORACLE_LISTENER_PORT='${ORACLE_LISTENER_PORT:-1521}'
bash /root/oracle26ai-install.sh
" &
  msg_info "Oracle install started in VM (takes 10-30 min depending on image choice and internet speed)"
  msg_info "Monitor progress: qm monitor ${VMID} → console"
else
  msg_warn "QEMU guest agent not ready. Install Oracle manually:"
  msg_warn "  ssh root@${VM_IP}"
  msg_warn "  bash /root/oracle26ai-install.sh"
fi

# Success summary
echo ""
msg_ok "======================================================="
msg_ok "Oracle AI Database 26ai VM Created!"
msg_ok "======================================================="
echo ""
echo "  VM ID:            ${VMID}"
echo "  Hostname:         ${HOSTNAME}"
echo "  IP Address:       ${VM_IP}"
echo ""
echo "  Connection String: ${VM_IP}:1521/FREEPDB1"
echo "  Monitor install:   ssh root@${VM_IP} 'tail -f /tmp/oracle-install.log'"
echo ""
echo "  Optional add-ons (run after Oracle is ready):"
echo "    APEX + ORDS:     bash scripts/setup-apex-ords.sh"
echo "    Vector Demo:     bash scripts/setup-vector-demo.sh"
echo ""
