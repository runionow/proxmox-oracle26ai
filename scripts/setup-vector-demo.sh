#!/usr/bin/env bash
# Oracle 26ai Vector Search Demo Loader
# Run AFTER Oracle 26ai is deployed and running
# Usage: bash scripts/setup-vector-demo.sh
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

load_env

# ============================================================
# CONFIGURATION
# ============================================================
CONTAINER_NAME="${ORACLE_CONTAINER_NAME:-oracle-26ai}"
ORACLE_PWD="${ORACLE_PWD:?'ORACLE_PWD must be set'}"
SQL_FILE="${SCRIPT_DIR}/../sql/vector-demo.sql"

# Detect container runtime
if command -v docker &>/dev/null; then
  RUNTIME="docker"
elif command -v podman &>/dev/null; then
  RUNTIME="podman"
else
  msg_error "No container runtime found."
fi

# ============================================================
# VERIFY ORACLE IS RUNNING
# ============================================================
msg_info "Checking Oracle container status..."
if ! $RUNTIME ps --filter "name=${CONTAINER_NAME}" --format '{{.Names}}' | grep -q "${CONTAINER_NAME}"; then
  msg_error "Oracle container '${CONTAINER_NAME}' is not running. Deploy it first: bash ct/oracle26ai.sh"
fi
msg_ok "Oracle container is running"

# Verify SQL file exists
if [[ ! -f "$SQL_FILE" ]]; then
  msg_error "Vector demo SQL file not found: ${SQL_FILE}"
fi
msg_ok "Vector demo SQL file found: ${SQL_FILE}"

# ============================================================
# LOAD VECTOR DEMO DATA
# ============================================================

# Copy SQL file into container
msg_info "Copying vector demo SQL to container..."
$RUNTIME cp "${SQL_FILE}" "${CONTAINER_NAME}:/tmp/vector-demo.sql"
msg_ok "SQL file copied to container"

# Execute SQL as SYSDBA
msg_info "Loading vector demo data into FREEPDB1..."
$RUNTIME exec "${CONTAINER_NAME}" bash -c "
  sqlplus -S sys/${ORACLE_PWD}@localhost:1521/FREEPDB1 as sysdba <<'SQLEOF'
  @/tmp/vector-demo.sql
  EXIT;
SQLEOF
" 2>&1 || {
  msg_warn "sqlplus execution may have had errors. Checking if table was created..."
}

# ============================================================
# VERIFY DATA LOADED
# ============================================================
msg_info "Verifying vector demo data..."
RECORD_COUNT=$($RUNTIME exec "${CONTAINER_NAME}" bash -c "
  sqlplus -S sys/${ORACLE_PWD}@localhost:1521/FREEPDB1 as sysdba <<'SQLEOF'
  SET HEADING OFF FEEDBACK OFF PAGESIZE 0
  SELECT COUNT(*) FROM vector_demo;
  EXIT;
SQLEOF
" 2>/dev/null | tr -d '[:space:]' | grep -o '[0-9]*' | head -1) || RECORD_COUNT="0"

if [[ -n "$RECORD_COUNT" ]] && [[ "$RECORD_COUNT" -gt "0" ]]; then
  msg_ok "Vector demo loaded: ${RECORD_COUNT} records in vector_demo table"
else
  msg_warn "Could not verify record count. Table may not have loaded correctly."
  msg_warn "Check manually: $RUNTIME exec ${CONTAINER_NAME} sqlplus sys/${ORACLE_PWD}@FREEPDB1 as sysdba"
fi

# ============================================================
# RUN DEMO QUERIES
# ============================================================
msg_info "Running sample vector search queries..."
echo ""
echo "--- Sample Query: Top 5 similar documents ---"
$RUNTIME exec "${CONTAINER_NAME}" bash -c "
  sqlplus -S sys/${ORACLE_PWD}@localhost:1521/FREEPDB1 as sysdba <<'SQLEOF'
  SET LINESIZE 100 PAGESIZE 20 HEADING ON
  SELECT title, category,
    ROUND(VECTOR_DISTANCE(embedding,
      (SELECT embedding FROM vector_demo WHERE ROWNUM = 1), COSINE), 4) AS distance
  FROM vector_demo
  WHERE ROWNUM > 1
  ORDER BY distance ASC
  FETCH FIRST 5 ROWS ONLY;
  EXIT;
SQLEOF
" 2>/dev/null || msg_warn "Demo query failed — Oracle DB may still be initializing"
echo ""

# ============================================================
# SUCCESS SUMMARY
# ============================================================
msg_ok "======================================================="
msg_ok "Vector Search Demo Loaded!"
msg_ok "======================================================="
echo ""
echo "  Table:    vector_demo (${RECORD_COUNT:-?} rows)"
echo "  PDB:      FREEPDB1"
echo ""
echo "  Explore the vector data:"
echo "    $RUNTIME exec -it ${CONTAINER_NAME} sqlplus sys/${ORACLE_PWD}@localhost:1521/FREEPDB1 as sysdba"
echo ""
echo "  Example queries are in: sql/vector-demo.sql"
echo ""
