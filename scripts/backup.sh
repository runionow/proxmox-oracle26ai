#!/usr/bin/env bash
# Oracle 26ai Database Backup Script
# Usage: bash scripts/backup.sh [backup-dir]
set -euo pipefail

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../misc/build.func" ]]; then
  # shellcheck source=../misc/build.func
  source "${SCRIPT_DIR}/../misc/build.func"
else
  source <(curl -fsSL https://raw.githubusercontent.com/YOURUSERNAME/proxmox-oracle26ai/main/misc/build.func)
fi

check_root
load_env

# ============================================================
# CONFIGURATION
# ============================================================
CONTAINER_NAME="${ORACLE_CONTAINER_NAME:-oracle-26ai}"
ORACLE_PWD="${ORACLE_PWD:?'ORACLE_PWD must be set'}"
BACKUP_DIR="${1:-/var/backups/oracle-26ai}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="oracle26ai_${TIMESTAMP}.dmp"
LOG_FILE="oracle26ai_${TIMESTAMP}.log"

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

# Create backup directory
mkdir -p "${BACKUP_DIR}"
msg_ok "Backup directory: ${BACKUP_DIR}"

# ============================================================
# RUN DATA PUMP EXPORT
# ============================================================
msg_info "Starting Oracle Data Pump export..."
msg_info "This may take several minutes depending on database size..."

# Run expdp inside container
$RUNTIME exec "${CONTAINER_NAME}" bash -c "
  expdp sys/${ORACLE_PWD}@localhost:1521/FREEPDB1 as sysdba \
    directory=DATA_PUMP_DIR \
    dumpfile=${BACKUP_FILE} \
    logfile=${LOG_FILE} \
    full=y \
    reuse_dumpfiles=yes 2>&1
" || {
  msg_warn "expdp may have encountered non-fatal errors. Checking for dump file..."
}

# ============================================================
# COPY BACKUP OUT OF CONTAINER
# ============================================================
msg_info "Copying backup file from container..."

# Find the DATA_PUMP_DIR path inside container
DPDUMP_PATH=$($RUNTIME exec "${CONTAINER_NAME}" bash -c \
  "sqlplus -S sys/${ORACLE_PWD}@localhost:1521/FREEPDB1 as sysdba <<'EOF'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT directory_path FROM dba_directories WHERE directory_name='DATA_PUMP_DIR';
EXIT;
EOF
" 2>/dev/null | tr -d '[:space:]') || DPDUMP_PATH="/opt/oracle/admin/FREE/dpdump"

# Default fallback path
[[ -z "$DPDUMP_PATH" ]] && DPDUMP_PATH="/opt/oracle/admin/FREE/dpdump"

$RUNTIME cp "${CONTAINER_NAME}:${DPDUMP_PATH}/${BACKUP_FILE}" "${BACKUP_DIR}/${BACKUP_FILE}" || {
  # Try alternate path
  $RUNTIME cp "${CONTAINER_NAME}:/opt/oracle/admin/FREE/dpdump/${BACKUP_FILE}" \
    "${BACKUP_DIR}/${BACKUP_FILE}" || \
  msg_error "Could not copy backup file. Check: $RUNTIME exec ${CONTAINER_NAME} ls ${DPDUMP_PATH}/"
}

# Copy log file too
$RUNTIME cp "${CONTAINER_NAME}:${DPDUMP_PATH}/${LOG_FILE}" \
  "${BACKUP_DIR}/${LOG_FILE}" 2>/dev/null || true

BACKUP_SIZE=$(du -sh "${BACKUP_DIR}/${BACKUP_FILE}" 2>/dev/null | awk '{print $1}' || echo "unknown")

msg_ok "======================================================="
msg_ok "Backup Complete!"
msg_ok "======================================================="
echo ""
echo "  Backup file: ${BACKUP_DIR}/${BACKUP_FILE}"
echo "  Size:        ${BACKUP_SIZE}"
echo "  Log:         ${BACKUP_DIR}/${LOG_FILE}"
echo ""
echo "  To restore: bash scripts/restore.sh ${BACKUP_DIR}/${BACKUP_FILE}"
echo ""
