#!/usr/bin/env bash
# ==============================================================================
# Script 06: Test Dynamic Persistent Storage on Ceph RBD via Proxmox CSI
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

INSTALL_DIR="${REPO_ROOT}/install-dir"
KUBECONFIG_FILE="${INSTALL_DIR}/auth/kubeconfig"
PVE_SSH="${PVE_USER}@${PVE_HOST}"

if [[ -f "${KUBECONFIG_FILE}" ]]; then
    export KUBECONFIG="${KUBECONFIG_FILE}"
fi

OC_BIN="oc"
if ! command -v "${OC_BIN}" &>/dev/null; then
    OC_BIN="${REPO_ROOT}/bin/oc"
fi

TEST_NS="mickey17-storage-test"

echo "=================================================="
echo "== Testing Dynamic Ceph RBD Provisioning via CSI =="
echo "=================================================="

# 1. Create test namespace
echo "[*] Creating namespace '${TEST_NS}'..."
"${OC_BIN}" create namespace "${TEST_NS}" --dry-run=client -o yaml | "${OC_BIN}" apply -f -

# 2. Deploy Test PVC and Pod
echo "[*] Creating Test PersistentVolumeClaim on Ceph RBD..."
"${OC_BIN}" apply -n "${TEST_NS}" -f "${REPO_ROOT}/pve-csi/test-pvc.yaml"

echo "[*] Deploying test consumer Pod..."
"${OC_BIN}" apply -n "${TEST_NS}" -f "${REPO_ROOT}/pve-csi/test-pod.yaml"

# 3. Wait for PVC Binding
echo "[*] Waiting for PVC to bind dynamically on Ceph RBD..."
TIMEOUT=120
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
    PHASE=$("${OC_BIN}" -n "${TEST_NS}" get pvc ceph-rbd-demo-pvc -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [[ "${PHASE}" == "Bound" ]]; then
        echo "[✓] PVC is Bound!"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo "    Waiting... (${ELAPSED}s/${TIMEOUT}s, status: ${PHASE:-Pending})"
done

if [[ "${PHASE:-}" != "Bound" ]]; then
    echo "[!] Error: PVC did not reach Bound state within ${TIMEOUT}s."
    "${OC_BIN}" -n "${TEST_NS}" describe pvc ceph-rbd-demo-pvc
    exit 1
fi

VOLUME_NAME=$("${OC_BIN}" -n "${TEST_NS}" get pvc ceph-rbd-demo-pvc -o jsonpath='{.spec.volumeName}')
echo "[✓] Dynamically provisioned PV: ${VOLUME_NAME}"

# 4. Wait for Pod to be Running
echo "[*] Waiting for test Pod to reach Running state..."
"${OC_BIN}" -n "${TEST_NS}" wait --for=condition=Ready pod/ceph-rbd-demo-pod --timeout=180s

# 5. Verify write/read inside Pod
echo "[*] Reading benchmark file written on Ceph volume..."
"${OC_BIN}" -n "${TEST_NS}" exec pod/ceph-rbd-demo-pod -- cat /mnt/ceph-data/success.txt

# 6. Verify volume in Proxmox Ceph RBD storage pool
echo "=================================================="
echo "== Proxmox Ceph Storage Verification =="
echo "=================================================="
ssh "${PVE_SSH}" "pvesm list ${PVE_STORAGE_CEPH_RBD} | grep '${VOLUME_NAME}' || pvesm list ${PVE_STORAGE_CEPH_RBD}"

echo "[✓] Ceph Block Storage Dynamic Provisioning is fully functional!"
