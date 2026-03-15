#!/usr/bin/env bash
# Oracle ORDS SSL/TLS Setup (Self-Signed Certificate)
# Run AFTER setup-apex-ords.sh has been executed
# Usage: bash scripts/setup-ssl.sh [hostname]
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
# CONFIGURATION
# ============================================================
CONTAINER_NAME="${ORACLE_CONTAINER_NAME:-oracle-26ai}"
SSL_PORT="${ORACLE_ORDS_SSL_PORT:-8443}"
HOSTNAME_ARG="${1:-${CT_HOSTNAME:-oracle26ai}}"
ORACLE_PWD="${ORACLE_PWD:?'ORACLE_PWD must be set'}"

# Detect runtime
if command -v docker &>/dev/null; then RUNTIME="docker"
elif command -v podman &>/dev/null; then RUNTIME="podman"
else msg_error "No container runtime found."; fi

# ============================================================
# VERIFY ORACLE CONTAINER IS RUNNING
# ============================================================
msg_info "Checking Oracle container..."
if ! $RUNTIME ps --filter "name=${CONTAINER_NAME}" --format '{{.Names}}' | grep -q "${CONTAINER_NAME}"; then
  msg_error "Oracle container '${CONTAINER_NAME}' is not running."
fi
msg_ok "Oracle container is running"

# ============================================================
# GENERATE SELF-SIGNED CERTIFICATE ON HOST
# ============================================================
msg_info "Generating self-signed SSL certificate..."

# Check openssl is available
if ! command -v openssl &>/dev/null; then
  msg_info "Installing openssl..."
  apt-get install -y -qq openssl 2>/dev/null || \
  yum install -y -q openssl 2>/dev/null || \
  msg_error "openssl not found and could not be installed. Install it: apt-get install openssl"
fi

# Generate private key and self-signed certificate (1 year validity)
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout /tmp/oracle-ssl.key \
  -out /tmp/oracle-ssl.crt \
  -subj "/CN=${HOSTNAME_ARG}/O=Oracle26ai/C=US" \
  -addext "subjectAltName=DNS:${HOSTNAME_ARG},DNS:localhost,IP:127.0.0.1" \
  2>/dev/null

msg_ok "Self-signed certificate generated (CN=${HOSTNAME_ARG}, valid 365 days)"

# ============================================================
# COPY CERTIFICATES INTO CONTAINER
# ============================================================
msg_info "Copying certificates into Oracle container..."
$RUNTIME cp /tmp/oracle-ssl.key "${CONTAINER_NAME}:/opt/oracle/ords/config/ssl.key"
$RUNTIME cp /tmp/oracle-ssl.crt "${CONTAINER_NAME}:/opt/oracle/ords/config/ssl.crt"

# Set proper permissions inside container
$RUNTIME exec "${CONTAINER_NAME}" bash -c "
  chmod 600 /opt/oracle/ords/config/ssl.key
  chmod 644 /opt/oracle/ords/config/ssl.crt
  chown oracle:oinstall /opt/oracle/ords/config/ssl.key /opt/oracle/ords/config/ssl.crt 2>/dev/null || true
" 2>/dev/null || true

msg_ok "Certificates copied to container"

# Clean up temp files
rm -f /tmp/oracle-ssl.key /tmp/oracle-ssl.crt

# ============================================================
# CONVERT TO PKCS12 KEYSTORE (ORDS format)
# ============================================================
msg_info "Creating PKCS12 keystore for ORDS..."
$RUNTIME exec "${CONTAINER_NAME}" bash -c "
  # Check if openssl is available in container
  if command -v openssl &>/dev/null; then
    openssl pkcs12 -export \
      -in /opt/oracle/ords/config/ssl.crt \
      -inkey /opt/oracle/ords/config/ssl.key \
      -out /opt/oracle/ords/config/ords.p12 \
      -name oracle-ords-ssl \
      -passout pass:OracleORDS1! 2>/dev/null
  else
    apt-get install -y -qq openssl 2>/dev/null || true
    openssl pkcs12 -export \
      -in /opt/oracle/ords/config/ssl.crt \
      -inkey /opt/oracle/ords/config/ssl.key \
      -out /opt/oracle/ords/config/ords.p12 \
      -name oracle-ords-ssl \
      -passout pass:OracleORDS1! 2>/dev/null || true
  fi
" 2>/dev/null || msg_warn "PKCS12 keystore creation failed. ORDS may use PEM certs directly."

msg_ok "PKCS12 keystore created"

# ============================================================
# RESTART ORDS WITH SSL
# ============================================================
msg_info "Stopping existing ORDS instance (if running)..."
$RUNTIME exec "${CONTAINER_NAME}" bash -c "
  pkill -f 'ords serve' 2>/dev/null || true
" 2>/dev/null || true
sleep 3

msg_info "Starting ORDS with SSL on port ${SSL_PORT}..."

# Find ORDS binary
ORDS_BIN=$($RUNTIME exec "${CONTAINER_NAME}" bash -c "
  find /opt/oracle -name 'ords' -type f 2>/dev/null | head -1 || echo '/opt/oracle/ords/bin/ords'
" 2>/dev/null || echo "/opt/oracle/ords/bin/ords")

$RUNTIME exec -d "${CONTAINER_NAME}" bash -c "
  ${ORDS_BIN} --config /opt/oracle/ords/config serve \
    --port ${SSL_PORT} \
    --secure \
    --keystore-path /opt/oracle/ords/config/ords.p12 \
    --keystore-password OracleORDS1! \
    > /tmp/ords-ssl.log 2>&1
" || {
  # Fallback: try with PEM certs directly
  $RUNTIME exec -d "${CONTAINER_NAME}" bash -c "
    ${ORDS_BIN} --config /opt/oracle/ords/config serve \
      --port ${SSL_PORT} \
      --certificate-path /opt/oracle/ords/config/ssl.crt \
      --private-key-path /opt/oracle/ords/config/ssl.key \
      > /tmp/ords-ssl.log 2>&1
  " 2>/dev/null || msg_warn "ORDS SSL start command not confirmed. Check /tmp/ords-ssl.log"
}

# Wait for ORDS to start with SSL
msg_info "Waiting for ORDS SSL endpoint (up to 30s)..."
SSL_ELAPSED=0
SSL_STARTED=false
while [[ $SSL_ELAPSED -lt 30 ]]; do
  if $RUNTIME exec "${CONTAINER_NAME}" bash -c \
      "curl -sk https://localhost:${SSL_PORT}/ords/ -o /dev/null -w '%{http_code}'" \
      2>/dev/null | grep -qE "^2|^3"; then
    SSL_STARTED=true
    break
  fi
  sleep 5
  ((SSL_ELAPSED+=5))
done

if [[ "$SSL_STARTED" == "true" ]]; then
  msg_ok "ORDS SSL endpoint is responding"
else
  msg_warn "ORDS SSL health check inconclusive. Check: $RUNTIME exec ${CONTAINER_NAME} cat /tmp/ords-ssl.log"
fi

# Get container IP
CONTAINER_IP=$($RUNTIME exec "${CONTAINER_NAME}" hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")

# ============================================================
# SUCCESS SUMMARY
# ============================================================
echo ""
msg_ok "======================================================="
msg_ok "SSL/TLS Configuration Complete!"
msg_ok "======================================================="
echo ""
echo "  HTTPS URL:  https://${CONTAINER_IP}:${SSL_PORT}/ords/"
echo "  Certificate: Self-signed (CN=${HOSTNAME_ARG}, 365 days)"
echo ""
msg_warn "IMPORTANT: This is a self-signed certificate."
msg_warn "Browsers will show a security warning — this is expected."
msg_warn "Add an exception or use: curl -sk https://${CONTAINER_IP}:${SSL_PORT}/ords/"
echo ""
echo "  SSL logs: $RUNTIME exec ${CONTAINER_NAME} cat /tmp/ords-ssl.log"
echo ""
echo "  To restart ORDS with SSL:"
echo "    $RUNTIME exec -d ${CONTAINER_NAME} bash -c '${ORDS_BIN} --config /opt/oracle/ords/config serve --port ${SSL_PORT} --secure > /tmp/ords-ssl.log 2>&1'"
echo ""
