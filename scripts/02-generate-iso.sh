#!/usr/bin/env bash
# ==============================================================================
# Script 02: Generate Bootable Agent Installer ISO for OKD SNO mickey17
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source environment
if [[ -f "${REPO_ROOT}/env.sh" ]]; then
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/env.sh"
else
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/env.sh.example"
fi

PVE_SSH="${PVE_USER}@${PVE_HOST}"
INSTALL_DIR="${REPO_ROOT}/install-dir"

echo "=================================================="
echo "== Generating OKD SNO Agent Installer ISO =="
echo "=================================================="

# Check openshift-install binary
INSTALLER_BIN="openshift-install"
if ! command -v "${INSTALLER_BIN}" &>/dev/null; then
    if [[ -x "${REPO_ROOT}/bin/openshift-install" ]]; then
        INSTALLER_BIN="${REPO_ROOT}/bin/openshift-install"
    else
        echo "[!] openshift-install not found. Running 00-install-tools.sh..."
        "${REPO_ROOT}/scripts/00-install-tools.sh"
    fi
fi

# Clean and prepare install-dir
echo "[*] Preparing assets in ${INSTALL_DIR}..."
rm -rf "${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"

# Copy install-config and agent-config
cp "${REPO_ROOT}/install-config.yaml" "${INSTALL_DIR}/install-config.yaml"
cp "${REPO_ROOT}/agent-config.yaml" "${INSTALL_DIR}/agent-config.yaml"

# Ensure SSH Key is injected if needed
if [[ -f "${SSH_KEY_FILE}" ]]; then
    PUB_KEY=$(cat "${SSH_KEY_FILE}")
    if ! grep -q "${PUB_KEY}" "${INSTALL_DIR}/install-config.yaml"; then
        echo "[*] Injecting SSH public key from ${SSH_KEY_FILE}..."
        sed -i "/^sshKey:/c\sshKey: '${PUB_KEY}'" "${INSTALL_DIR}/install-config.yaml"
    fi
fi

echo "[*] Generating Agent-based Installer ISO (this extracts base image and embeds SNO ignition)..."
"${INSTALLER_BIN}" agent create image --dir="${INSTALL_DIR}" --log-level=info

GENERATED_ISO="${INSTALL_DIR}/agent.x86_64.iso"
if [[ ! -f "${GENERATED_ISO}" ]]; then
    echo "[!] Error: Expected generated ISO at ${GENERATED_ISO} not found!"
    exit 1
fi

ISO_SIZE=$(du -h "${GENERATED_ISO}" | cut -f1)
echo "[✓] Agent installer ISO generated successfully (${ISO_SIZE})."

# Transfer ISO to Proxmox ISO storage pool (CephFS or local)
REMOTE_ISO_NAME="agent-${CLUSTER_NAME}.iso"
echo "[*] Transferring installer ISO to Proxmox CephFS storage (${PVE_HOST})..."

# Check if cephfs template directory exists, otherwise fallback to local vz
REMOTE_ISO_DIR=$(ssh "${PVE_SSH}" bash -s << 'EOF'
if [ -d "/mnt/pve/cephfs/template/iso" ]; then
    echo "/mnt/pve/cephfs/template/iso"
else
    echo "/var/lib/vz/template/iso"
fi
EOF
)

echo "[*] Target remote ISO directory: ${REMOTE_ISO_DIR}"
scp -C "${GENERATED_ISO}" "${PVE_SSH}:${REMOTE_ISO_DIR}/${REMOTE_ISO_NAME}"

# Verify Proxmox recognizes the ISO
echo "[*] Verifying ISO in Proxmox storage pool..."
ssh "${PVE_SSH}" "pvesm list ${PVE_STORAGE_ISO} | grep '${REMOTE_ISO_NAME}' || pvesm list local | grep '${REMOTE_ISO_NAME}'"

echo "[✓] Installer ISO ready on Proxmox: ${PVE_STORAGE_ISO}:iso/${REMOTE_ISO_NAME}"
echo "=================================================="
echo "== Agent Installer ISO Preparation Complete =="
echo "=================================================="
