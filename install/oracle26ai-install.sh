#!/usr/bin/env bash
# Oracle AI Database 26ai - Installation Script
# Runs INSIDE LXC container or KVM VM after creation
# Called by: ct/oracle26ai.sh or ct/oracle26ai-vm.sh
set -euo pipefail

# Simplified messaging (standalone - not sourcing build.func)
YW='\033[33m' GN='\033[32m' RD='\033[31m' CL='\033[m'
CM='\xE2\x9C\x94' CROSS='\xE2\x9C\x97' HOLD='-'

msg_info() { echo -ne " ${HOLD} ${YW}${1}${CL}\r"; }
msg_ok()   { echo -e  " ${CM} ${GN}${1}${CL}"; }
msg_error(){ echo -e  " ${CROSS} ${RD}${1}${CL}"; exit 1; }
msg_warn() { echo -e  " ${HOLD} ${YW}WARNING: ${1}${CL}"; }

ORACLE_IMAGE_TAG="${ORACLE_IMAGE_TAG:-23.26.0.0}"
ORACLE_PWD="${ORACLE_PWD:?'ORACLE_PWD must be set'}"
ORACLE_CONTAINER_NAME="${ORACLE_CONTAINER_NAME:-oracle-26ai}"
ORACLE_LISTENER_PORT="${ORACLE_LISTENER_PORT:-1521}"
RUNTIME=""

msg_info "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  ca-certificates curl gnupg lsb-release \
  apt-transport-https software-properties-common \
  net-tools iproute2
msg_ok "Prerequisites installed"

detect_install_runtime() {
  if command -v docker &>/dev/null; then
    RUNTIME="docker"
    msg_ok "Docker detected: $(docker --version | awk 'NR==1{print}')"
  elif command -v podman &>/dev/null; then
    RUNTIME="podman"
    msg_warn "Podman detected. Docker is preferred. Some features may differ."
  else
    msg_info "Installing Docker CE for Debian..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
    chmod a+r /etc/apt/keyrings/docker.gpg

    local codename
    codename="bookworm"
    if [[ -r /etc/os-release ]]; then
      codename=$(awk -F= '/^VERSION_CODENAME=/{gsub(/"/,"",$2);print $2}' /etc/os-release)
      codename="${codename:-bookworm}"
    fi

    printf '%s\n' "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${codename} stable" \
      > /etc/apt/sources.list.d/docker.list

    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin
    systemctl enable --now docker
    RUNTIME="docker"
    msg_ok "Docker CE installed and started"
  fi
  export RUNTIME
}

detect_install_runtime

msg_info "Checking shared memory (/dev/shm) size..."
SHM_SIZE_KB=$(df -k /dev/shm 2>/dev/null | awk 'NR==2{print $2}' || echo "0")
SHM_SIZE_GB=$(( SHM_SIZE_KB / 1024 / 1024 ))

if [[ ${SHM_SIZE_GB} -lt 1 ]]; then
  msg_warn "/dev/shm size is ${SHM_SIZE_GB}GB (less than 1GB). Attempting to increase..."
  if mount -o remount,size=2g /dev/shm 2>/dev/null; then
    msg_ok "/dev/shm remounted to 2GB"
  else
    msg_warn "Could not resize /dev/shm. Oracle may experience issues. Continuing..."
  fi
else
  msg_ok "/dev/shm size OK: ${SHM_SIZE_GB}GB"
fi

ORACLE_IMAGE="container-registry.oracle.com/database/free:${ORACLE_IMAGE_TAG}"
msg_info "Pulling Oracle 26ai image: ${ORACLE_IMAGE}"
msg_info "Image size: ~10GB (full) or ~2GB (lite). This may take 10-30 minutes..."
echo ""

if ! pull_output=$($RUNTIME pull "${ORACLE_IMAGE}" 2>&1); then
  if printf '%s\n' "${pull_output}" | grep -Eqi "unauthorized|authentication|access denied|denied: requested access"; then
    msg_error "Oracle Container Registry authentication required.

Please accept the Oracle Free license terms:
1. Visit: https://container-registry.oracle.com
2. Sign in with your Oracle account (free to create)
3. Navigate to: Database -> Free
4. Accept the license agreement
5. Run: ${RUNTIME} login container-registry.oracle.com
6. Re-run this script"
  fi

  echo "${pull_output}"
  msg_error "Failed to pull Oracle image: ${ORACLE_IMAGE}
Check: ${RUNTIME} pull ${ORACLE_IMAGE}"
fi
msg_ok "Oracle image pulled successfully"

msg_info "Starting Oracle AI Database 26ai container..."
$RUNTIME run -d \
  --name "${ORACLE_CONTAINER_NAME}" \
  -p "${ORACLE_LISTENER_PORT}:1521" \
  -e ORACLE_PWD="${ORACLE_PWD}" \
  --shm-size=1g \
  -v oracle_data:/opt/oracle/oradata \
  --restart unless-stopped \
  "${ORACLE_IMAGE}"
msg_ok "Oracle container started"

msg_info "Waiting for Oracle Database to initialize (this takes 3-8 minutes on first start)..."
TIMEOUT=600
ELAPSED=0
INTERVAL=10

while [[ ${ELAPSED} -lt ${TIMEOUT} ]]; do
  if $RUNTIME logs "${ORACLE_CONTAINER_NAME}" 2>&1 | grep -q "DATABASE IS READY TO USE!"; then
    break
  fi

  STATUS=$($RUNTIME inspect -f '{{.State.Status}}' "${ORACLE_CONTAINER_NAME}" 2>/dev/null || echo "missing")
  if [[ "${STATUS}" == "exited" || "${STATUS}" == "dead" ]]; then
    msg_error "Oracle container stopped unexpectedly. Check logs: $RUNTIME logs ${ORACLE_CONTAINER_NAME}"
  fi

  sleep "${INTERVAL}"
  ELAPSED=$((ELAPSED + INTERVAL))

  if (( ELAPSED % 30 == 0 )); then
    msg_info "Still initializing... (${ELAPSED}s elapsed, timeout: ${TIMEOUT}s)"
  fi
done

if [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
  msg_error "Oracle failed to start within ${TIMEOUT}s. Check logs: $RUNTIME logs ${ORACLE_CONTAINER_NAME}"
fi
msg_ok "Oracle Database initialized successfully! (${ELAPSED}s)"

msg_info "Verifying Oracle connectivity..."
VERIFY_RESULT=$($RUNTIME exec "${ORACLE_CONTAINER_NAME}" bash -c \
  "echo 'SELECT 1 FROM dual;' | sqlplus -S sys/${ORACLE_PWD}@localhost:1521/FREEPDB1 as sysdba 2>/dev/null" \
  2>/dev/null || echo "FAILED")

if printf '%s\n' "${VERIFY_RESULT}" | grep -Eq '^1$|[[:space:]]1$'; then
  msg_ok "Oracle connectivity verified - SELECT 1 FROM dual returned: 1"
else
  msg_warn "Connectivity check inconclusive (sqlplus may not be in PATH). Oracle is running."
  msg_warn "Test manually: $RUNTIME exec ${ORACLE_CONTAINER_NAME} sqlplus sys/${ORACLE_PWD}@FREEPDB1 as sysdba"
fi

echo ""
msg_ok "=========================================="
msg_ok "Oracle AI Database 26ai is READY!"
msg_ok "=========================================="
echo ""
echo "  Container:  ${ORACLE_CONTAINER_NAME}"
echo "  Port:       ${ORACLE_LISTENER_PORT}"
echo "  PDB:        FREEPDB1"
echo "  Service:    FREE"
echo ""
echo "  Connect with sqlplus:"
echo "    sqlplus sys/\$ORACLE_PWD@localhost:${ORACLE_LISTENER_PORT}/FREEPDB1 as sysdba"
echo ""
echo "  Container logs:"
echo "    $RUNTIME logs ${ORACLE_CONTAINER_NAME}"
echo ""
echo "  Stop Oracle:"
echo "    $RUNTIME stop ${ORACLE_CONTAINER_NAME}"
echo ""
