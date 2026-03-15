#!/usr/bin/env bash
# Oracle AI Database 26ai — Uninstall/Cleanup Script
# Removes Oracle 26ai deployment from Proxmox
# Usage: bash scripts/uninstall.sh [VMID]
set -euo pipefail

# Source shared functions
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

check_root
check_proxmox
load_env

# ============================================================
# CONFIGURATION
# ============================================================
VMID="${1:-}"
CONTAINER_NAME="${ORACLE_CONTAINER_NAME:-oracle-26ai}"

# Detect container runtime
if command -v docker &>/dev/null; then RUNTIME="docker"
elif command -v podman &>/dev/null; then RUNTIME="podman"
else RUNTIME="docker"; fi

# ============================================================
# FIND VMID IF NOT PROVIDED
# ============================================================
if [[ -z "$VMID" ]]; then
  msg_info "Searching for Oracle 26ai deployment..."
  
  # Look for containers/VMs named oracle26ai
  LXC_VMID=$(pct list 2>/dev/null | awk '/oracle26ai/ {print $1}' | head -1) || LXC_VMID=""
  VM_VMID=$(qm list 2>/dev/null | awk '/oracle26ai/ {print $1}' | head -1) || VM_VMID=""
  
  if [[ -n "$LXC_VMID" ]]; then
    VMID="$LXC_VMID"
    DEPLOY_TYPE="lxc"
    msg_ok "Found LXC container: VMID ${VMID}"
  elif [[ -n "$VM_VMID" ]]; then
    VMID="$VM_VMID"
    DEPLOY_TYPE="vm"
    msg_ok "Found KVM VM: VMID ${VMID}"
  else
    msg_warn "No Oracle 26ai deployment found (searched for hostname 'oracle26ai')."
    echo ""
    echo "  To specify a VMID manually: bash scripts/uninstall.sh <VMID>"
    echo "  To list all containers:     pct list"
    echo "  To list all VMs:            qm list"
    exit 0
  fi
else
  # Determine type from provided VMID
  if pct status "${VMID}" &>/dev/null; then
    DEPLOY_TYPE="lxc"
    msg_ok "VMID ${VMID} is an LXC container"
  elif qm status "${VMID}" &>/dev/null; then
    DEPLOY_TYPE="vm"
    msg_ok "VMID ${VMID} is a KVM VM"
  else
    msg_error "VMID ${VMID} not found. Check: pct list && qm list"
  fi
fi

# ============================================================
# CONFIRMATION PROMPT (destructive operation — MANDATORY)
# ============================================================
echo ""
msg_warn "======================================================"
msg_warn "WARNING: This will PERMANENTLY DESTROY:"
msg_warn "  - The Oracle 26ai ${DEPLOY_TYPE^^} (VMID: ${VMID})"
msg_warn "  - All Oracle data in the Docker volume"
msg_warn "  - All configuration"
msg_warn "======================================================"
echo ""

CONFIRMED=false
if command -v whiptail &>/dev/null; then
  if whiptail --title "Confirm Uninstall" \
    --yesno "PERMANENTLY destroy Oracle 26ai deployment?\n\n  VMID: ${VMID}\n  Type: ${DEPLOY_TYPE^^}\n\nThis CANNOT be undone. All Oracle data will be lost." \
    14 60 3>&1 1>&2 2>&3; then
    CONFIRMED=true
  fi
else
  read -r -p "Type 'destroy' to confirm permanent deletion: " CONFIRM_INPUT
  [[ "$CONFIRM_INPUT" == "destroy" ]] && CONFIRMED=true
fi

if [[ "$CONFIRMED" != "true" ]]; then
  msg_warn "Uninstall cancelled. No changes made."
  exit 0
fi

# ============================================================
# STOP ORACLE CONTAINER INSIDE LXC/VM (graceful shutdown)
# ============================================================
msg_info "Stopping Oracle container inside ${DEPLOY_TYPE^^}..."

if [[ "$DEPLOY_TYPE" == "lxc" ]]; then
  pct exec "${VMID}" -- bash -c "
    ${RUNTIME} stop ${CONTAINER_NAME} 2>/dev/null || true
    ${RUNTIME} rm -f ${CONTAINER_NAME} 2>/dev/null || true
    ${RUNTIME} volume rm oracle_data 2>/dev/null || true
  " 2>/dev/null || msg_warn "Could not stop Oracle container (may already be stopped)"
else
  qm guest exec "${VMID}" -- bash -c "
    ${RUNTIME} stop ${CONTAINER_NAME} 2>/dev/null || true
    ${RUNTIME} rm -f ${CONTAINER_NAME} 2>/dev/null || true
    ${RUNTIME} volume rm oracle_data 2>/dev/null || true
  " 2>/dev/null || msg_warn "Could not stop Oracle container (VM may not be responding)"
fi
msg_ok "Oracle container stopped"

# ============================================================
# DESTROY LXC/VM
# ============================================================
if [[ "$DEPLOY_TYPE" == "lxc" ]]; then
  msg_info "Stopping LXC container (VMID: ${VMID})..."
  pct stop "${VMID}" 2>/dev/null || true
  sleep 3
  msg_info "Destroying LXC container (VMID: ${VMID})..."
  pct destroy "${VMID}" --purge 2>/dev/null || pct destroy "${VMID}"
else
  msg_info "Stopping KVM VM (VMID: ${VMID})..."
  qm stop "${VMID}" 2>/dev/null || true
  sleep 5
  msg_info "Destroying KVM VM (VMID: ${VMID})..."
  qm destroy "${VMID}" --purge 2>/dev/null || qm destroy "${VMID}"
fi

msg_ok "VMID ${VMID} destroyed"

# ============================================================
# OPTIONAL: REMOVE BACKUP FILES
# ============================================================
BACKUP_DIR="/var/backups/oracle-26ai"
if [[ -d "$BACKUP_DIR" ]]; then
  if command -v whiptail &>/dev/null; then
    if whiptail --title "Remove Backups?" \
      --yesno "Remove backup files at ${BACKUP_DIR}?" \
      8 60 3>&1 1>&2 2>&3; then
      rm -rf "${BACKUP_DIR}"
      msg_ok "Backup directory removed: ${BACKUP_DIR}"
    else
      msg_warn "Backup files kept at: ${BACKUP_DIR}"
    fi
  else
    read -r -p "Remove backup files at ${BACKUP_DIR}? (y/N): " REMOVE_BACKUPS
    if [[ "${REMOVE_BACKUPS,,}" == "y" ]]; then
      rm -rf "${BACKUP_DIR}"
      msg_ok "Backup directory removed"
    fi
  fi
fi

# ============================================================
# SUCCESS SUMMARY
# ============================================================
echo ""
msg_ok "======================================================="
msg_ok "Oracle AI Database 26ai Uninstalled"
msg_ok "======================================================="
echo ""
echo "  Removed: ${DEPLOY_TYPE^^} VMID ${VMID} (oracle-26ai)"
echo ""
echo "  To redeploy:"
echo "    LXC: bash <(curl -fsSL .../ct/oracle26ai.sh)"
echo "    VM:  bash <(curl -fsSL .../ct/oracle26ai-vm.sh)"
echo ""
