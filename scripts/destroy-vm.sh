#!/usr/bin/env bash
# ==============================================================================
# Script: Destroy OKD SNO VM & Cleanup Ceph Storage
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

echo "=================================================="
echo "== Destroying OKD SNO VM ${VM_ID} on Proxmox (${PVE_HOST}) =="
echo "=================================================="

echo "[*] Stopping VM ${VM_ID}..."
ssh "${PVE_SSH}" "qm stop ${VM_ID} 2>/dev/null || true"
sleep 5

echo "[*] Purging VM ${VM_ID} and disks on Ceph RBD..."
ssh "${PVE_SSH}" "qm destroy ${VM_ID} --purge 1 2>/dev/null || true"

echo "[*] Cleaning up install-dir assets..."
rm -rf "${REPO_ROOT}/install-dir"

echo "[✓] VM ${VM_ID} and local assets removed successfully."
