#!/usr/bin/env bash
# Oracle APEX + ORDS Setup Module
# Run AFTER Oracle 26ai is deployed and running
# Usage: bash scripts/setup-apex-ords.sh
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
ORDS_PORT="${ORACLE_ORDS_PORT:-8080}"
ORACLE_PWD="${ORACLE_PWD:?'ORACLE_PWD must be set. Source .env or set it: export ORACLE_PWD=yourpassword'}"

# Detect container runtime
if command -v docker &>/dev/null; then
  RUNTIME="docker"
elif command -v podman &>/dev/null; then
  RUNTIME="podman"
else
  msg_error "No container runtime found. Install Docker first."
fi

# ============================================================
# VERIFY ORACLE IS RUNNING
# ============================================================
msg_info "Checking Oracle container status..."

if ! $RUNTIME ps --filter "name=${CONTAINER_NAME}" --format '{{.Names}}' | grep -q "${CONTAINER_NAME}"; then
  msg_error "Oracle container '${CONTAINER_NAME}' is not running.
  
  Start it with: $RUNTIME start ${CONTAINER_NAME}
  Or deploy a fresh instance: bash ct/oracle26ai.sh"
fi

# Verify DB is healthy
msg_info "Verifying Oracle Database health..."
if ! $RUNTIME logs "${CONTAINER_NAME}" 2>&1 | grep -q "DATABASE IS READY TO USE!"; then
  msg_warn "Oracle container is running but DB may still be initializing."
  msg_warn "Wait for 'DATABASE IS READY TO USE!' in logs: $RUNTIME logs ${CONTAINER_NAME}"
  msg_warn "Continuing anyway..."
fi
msg_ok "Oracle container '${CONTAINER_NAME}' is running"

# ============================================================
# CHECK FOR BUILT-IN ORDS
# ============================================================
msg_info "Checking for built-in ORDS in Oracle container..."
ORDS_BUILTIN=false
if $RUNTIME exec "${CONTAINER_NAME}" bash -c "ls /opt/oracle/ords/bin/ords 2>/dev/null" &>/dev/null; then
  ORDS_BUILTIN=true
  ORDS_BIN="/opt/oracle/ords/bin/ords"
  msg_ok "Built-in ORDS found at ${ORDS_BIN}"
fi

# ============================================================
# INSTALL JAVA (required for ORDS)
# ============================================================
msg_info "Installing Java 17 inside Oracle container..."
$RUNTIME exec "${CONTAINER_NAME}" bash -c "
  apt-get update -qq 2>/dev/null || yum update -q 2>/dev/null || true
  apt-get install -y -qq openjdk-17-jre-headless 2>/dev/null || \
  yum install -y -q java-17-openjdk-headless 2>/dev/null || true
" 2>/dev/null || msg_warn "Java install may have failed — ORDS requires Java 17"

# Verify Java
if $RUNTIME exec "${CONTAINER_NAME}" bash -c "java -version" &>/dev/null; then
  JAVA_VER=$($RUNTIME exec "${CONTAINER_NAME}" bash -c "java -version 2>&1 | head -1")
  msg_ok "Java available: ${JAVA_VER}"
else
  msg_warn "Java not detected. ORDS may not work."
fi

# ============================================================
# DOWNLOAD AND CONFIGURE ORDS (if not built-in)
# ============================================================
if [[ "$ORDS_BUILTIN" == "false" ]]; then
  msg_info "Downloading ORDS (latest) inside container..."
  $RUNTIME exec "${CONTAINER_NAME}" bash -c "
    cd /tmp
    curl -fsSL -o ords-latest.zip \
      'https://download.oracle.com/otn_software/java/ords/ords-latest.zip' 2>/dev/null || \
    { echo 'Direct download requires Oracle login. Using wget fallback...'; exit 1; }
  " || {
    msg_warn "ORDS direct download requires authentication."
    msg_warn "Manual steps:"
    msg_warn "  1. Download ORDS from: https://www.oracle.com/database/technologies/appdev/rest.html"
    msg_warn "  2. Copy into container: $RUNTIME cp ords-latest.zip ${CONTAINER_NAME}:/tmp/"
    msg_warn "  3. Re-run this script"
    
    # Try to use bundled ORDS from Oracle Free if available
    if $RUNTIME exec "${CONTAINER_NAME}" bash -c "ls /opt/oracle/product/*/dbhome_1/ords 2>/dev/null" &>/dev/null; then
      msg_ok "Found ORDS in Oracle home. Using it."
      ORDS_BIN=$($RUNTIME exec "${CONTAINER_NAME}" bash -c "find /opt/oracle -name 'ords' -type f 2>/dev/null | head -1")
      ORDS_BUILTIN=true
    else
      msg_error "ORDS not available. Please download ORDS manually and re-run."
    fi
  }
  
  if [[ "$ORDS_BUILTIN" == "false" ]]; then
    msg_info "Extracting ORDS..."
    $RUNTIME exec "${CONTAINER_NAME}" bash -c "
      mkdir -p /opt/oracle/ords
      cd /tmp && unzip -q ords-latest.zip -d /opt/oracle/ords/
    "
    ORDS_BIN="/opt/oracle/ords/bin/ords"
    msg_ok "ORDS extracted to /opt/oracle/ords/"
  fi
fi

# ============================================================
# CONFIGURE ORDS CONNECTION TO FREEPDB1
# ============================================================
msg_info "Configuring ORDS connection to FREEPDB1..."
$RUNTIME exec "${CONTAINER_NAME}" bash -c "
  mkdir -p /opt/oracle/ords/config
  ${ORDS_BIN} --config /opt/oracle/ords/config install \
    --admin-user SYS \
    --proxy-user \
    --db-hostname localhost \
    --db-port 1521 \
    --db-servicename FREEPDB1 \
    --feature-db-api true \
    --feature-rest-enabled-sql true \
    --feature-sdw true \
    --password-stdin <<< '${ORACLE_PWD}
${ORACLE_PWD}
oracle_ords
OracleORDS1!' 2>&1 || true
" 2>/dev/null || {
  msg_warn "ORDS interactive configuration may have issues."
  msg_warn "Check: $RUNTIME exec ${CONTAINER_NAME} ${ORDS_BIN} --config /opt/oracle/ords/config serve --help"
}

# ============================================================
# START ORDS
# ============================================================
msg_info "Starting ORDS on port ${ORDS_PORT}..."
$RUNTIME exec -d "${CONTAINER_NAME}" bash -c "
  ${ORDS_BIN} --config /opt/oracle/ords/config serve \
    --port ${ORDS_PORT} \
    --apex-images /opt/oracle/apex/images \
    > /tmp/ords.log 2>&1
" || {
  # Simpler start without APEX images
  $RUNTIME exec -d "${CONTAINER_NAME}" bash -c "
    ${ORDS_BIN} --config /opt/oracle/ords/config serve \
      --port ${ORDS_PORT} \
      > /tmp/ords.log 2>&1
  "
}

# Wait for ORDS to start
msg_info "Waiting for ORDS to start (up to 60s)..."
ORDS_TIMEOUT=60
ORDS_ELAPSED=0
while [[ $ORDS_ELAPSED -lt $ORDS_TIMEOUT ]]; do
  if $RUNTIME exec "${CONTAINER_NAME}" bash -c \
      "curl -sf http://localhost:${ORDS_PORT}/ords/ -o /dev/null -w '%{http_code}'" \
      2>/dev/null | grep -qE "^2|^3"; then
    break
  fi
  sleep 5
  ((ORDS_ELAPSED+=5))
done

if [[ $ORDS_ELAPSED -ge $ORDS_TIMEOUT ]]; then
  msg_warn "ORDS health check timed out. Check logs: $RUNTIME exec ${CONTAINER_NAME} cat /tmp/ords.log"
else
  msg_ok "ORDS started successfully"
fi

# ============================================================
# GET CONTAINER IP
# ============================================================
CONTAINER_IP=$($RUNTIME exec "${CONTAINER_NAME}" hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")

# ============================================================
# SUCCESS SUMMARY
# ============================================================
echo ""
msg_ok "======================================================="
msg_ok "Oracle APEX + ORDS Setup Complete!"
msg_ok "======================================================="
echo ""
echo "  ORDS URL:     http://${CONTAINER_IP}:${ORDS_PORT}/ords/"
echo "  APEX URL:     http://${CONTAINER_IP}:${ORDS_PORT}/ords/apex"
echo "  SQL Dev Web:  http://${CONTAINER_IP}:${ORDS_PORT}/ords/sql-developer"
echo ""
echo "  To restart ORDS after container restart:"
echo "    $RUNTIME exec -d ${CONTAINER_NAME} bash -c '${ORDS_BIN} --config /opt/oracle/ords/config serve --port ${ORDS_PORT} > /tmp/ords.log 2>&1'"
echo ""
echo "  ORDS logs:"
echo "    $RUNTIME exec ${CONTAINER_NAME} cat /tmp/ords.log"
echo ""
