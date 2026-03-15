#!/usr/bin/env bash
# Oracle 26ai Database Restore Script
# Usage: bash scripts/restore.sh <backup-file.dmp>
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
load_env

# ============================================================
# ARGUMENTS AND CONFIGURATION
# ============================================================
BACKUP_FILE="${1:?'Usage: bash scripts/restore.sh <path/to/backup.dmp>'}"

if [[ ! -f "$BACKUP_FILE" ]]; then
  msg_error "Backup file not found: ${BACKUP_FILE}"
fi

CONTAINER_NAME="${ORACLE_CONTAINER_NAME:-oracle-26ai}"
ORACLE_PWD="${ORACLE_PWD:?'ORACLE_PWD must be set'}"
BACKUP_NAME=$(basename "${BACKUP_FILE}")
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESTORE_LOG="oracle26ai_restore_${TIMESTAMP}.log"

# Detect runtime
if command -v docker &>/dev/null; then RUNTIME="docker"
elif command -v podman &>/dev/null; then RUNTIME="podman"
else msg_error "No container runtime found."; fi

# ============================================================
# VERIFY ORACLE IS RUNNING
# ============================================================
msg_info "Checking Oracle container..."
if ! $RUNTIME ps --filter "name=${CONTAINER_NAME}" --format '{{.Names}}' | grep -q "${CONTAINER_NAME}"; then
  msg_error "Oracle container '${CONTAINER_NAME}' is not running."
fi
msg_ok "Oracle container is running"

# ============================================================
# CONFIRM RESTORE (destructive operation)
# ============================================================
echo ""
msg_warn "WARNING: This will import data into FREEPDB1."
msg_warn "Existing objects may be dropped/overwritten if they conflict."
echo ""
echo "  Backup file: ${BACKUP_FILE}"
echo "  Target:      ${CONTAINER_NAME} → FREEPDB1"
echo ""

if command -v whiptail &>/dev/null; then
  whiptail --title "Confirm Restore" \
    --yesno "Restore database from:\n\n${BACKUP_FILE}\n\nThis operation may overwrite existing data. Continue?" \
    12 60 || { msg_warn "Restore cancelled."; exit 0; }
else
  read -r -p "Restore from ${BACKUP_NAME}? Type 'yes' to confirm: " CONFIRM
  [[ "$CONFIRM" != "yes" ]] && { msg_warn "Restore cancelled."; exit 0; }
fi

# ============================================================
# COPY BACKUP INTO CONTAINER
# ============================================================
DPDUMP_PATH="/opt/oracle/admin/FREE/dpdump"

msg_info "Copying backup file into container..."
$RUNTIME cp "${BACKUP_FILE}" "${CONTAINER_NAME}:${DPDUMP_PATH}/${BACKUP_NAME}"
msg_ok "Backup file copied to container"

# ============================================================
# RUN DATA PUMP IMPORT
# ============================================================
msg_info "Starting Oracle Data Pump import..."
msg_info "This may take several minutes..."

$RUNTIME exec "${CONTAINER_NAME}" bash -c "
  impdp sys/${ORACLE_PWD}@localhost:1521/FREEPDB1 as sysdba \
    directory=DATA_PUMP_DIR \
    dumpfile=${BACKUP_NAME} \
    logfile=${RESTORE_LOG} \
    full=y \
    table_exists_action=replace 2>&1
" || msg_warn "impdp may have encountered non-fatal errors. Check the log."

# ============================================================
# VERIFY RESTORE
# ============================================================
msg_info "Verifying restore..."
OBJECT_COUNT=$($RUNTIME exec "${CONTAINER_NAME}" bash -c "
  sqlplus -S sys/${ORACLE_PWD}@localhost:1521/FREEPDB1 as sysdba <<'EOF'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT COUNT(*) FROM dba_objects WHERE object_type IN ('TABLE','VIEW','INDEX');
EXIT;
EOF
" 2>/dev/null | tr -d '[:space:]' | grep -o '[0-9]*' | head -1) || OBJECT_COUNT="unknown"

msg_ok "======================================================="
msg_ok "Restore Complete!"
msg_ok "======================================================="
echo ""
echo "  Restored from: ${BACKUP_FILE}"
echo "  DB objects:    ${OBJECT_COUNT}"
echo "  Log:           $RUNTIME exec ${CONTAINER_NAME} cat ${DPDUMP_PATH}/${RESTORE_LOG}"
echo ""
