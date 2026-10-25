#!/usr/bin/env bash
# ==============================================================================
# Script 05: Deploy Proxmox CSI Plugin with Ceph Storage on OKD mickey17
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
CSI_CONFIG_FILE="${REPO_ROOT}/pve-csi/config.yaml"

if [[ -f "${KUBECONFIG_FILE}" ]]; then
    export KUBECONFIG="${KUBECONFIG_FILE}"
fi

OC_BIN="oc"
if ! command -v "${OC_BIN}" &>/dev/null; then
    OC_BIN="${REPO_ROOT}/bin/oc"
fi

echo "=================================================="
echo "== Deploying Proxmox CSI Plugin (Ceph RBD / CephFS) =="
echo "=================================================="

# Check CSI config file
if [[ ! -f "${CSI_CONFIG_FILE}" ]]; then
    echo "[!] Proxmox CSI config not found at ${CSI_CONFIG_FILE}. Running 01-prep-proxmox-ceph.sh..."
    "${REPO_ROOT}/scripts/01-prep-proxmox-ceph.sh"
fi

# 1. Label nodes with topology zone & region
echo "[*] Setting node topology labels..."
"${OC_BIN}" label nodes --all "topology.kubernetes.io/region=${CLUSTER_NAME}" --overwrite
"${OC_BIN}" label nodes --all "topology.kubernetes.io/zone=${PVE_NODE}" --overwrite

# 2. Create namespace csi-proxmox
echo "[*] Creating namespace 'csi-proxmox'..."
"${OC_BIN}" create namespace csi-proxmox --dry-run=client -o yaml | "${OC_BIN}" apply -f -
"${OC_BIN}" label ns csi-proxmox pod-security.kubernetes.io/enforce=privileged --overwrite

# 3. Create CSI Secret from config.yaml
echo "[*] Creating Proxmox CSI Secret..."
"${OC_BIN}" -n csi-proxmox create secret generic proxmox-csi-plugin \
    --from-file=config.yaml="${CSI_CONFIG_FILE}" \
    --dry-run=client -o yaml | "${OC_BIN}" apply -f -

# 4. Grant OpenShift Privileged Security Context Constraint (SCC) to CSI ServiceAccounts
echo "[*] Granting privileged SCC to Proxmox CSI service accounts..."
"${OC_BIN}" adm policy add-scc-to-user privileged -z proxmox-csi-plugin-controller -n csi-proxmox || true
"${OC_BIN}" adm policy add-scc-to-user privileged -z proxmox-csi-plugin-node -n csi-proxmox || true

# 5. Apply Proxmox CSI Plugin Release Manifests
echo "[*] Applying Proxmox CSI Controller and Node daemonset..."
"${OC_BIN}" apply -f https://raw.githubusercontent.com/sergelogvinov/proxmox-csi-plugin/main/docs/deploy/proxmox-csi-plugin-release.yml

# 6. Apply Ceph StorageClasses
echo "[*] Applying StorageClasses (Default: Ceph RBD)..."
"${OC_BIN}" apply -f "${REPO_ROOT}/pve-csi/storageclass-ceph-rbd.yaml"
"${OC_BIN}" apply -f "${REPO_ROOT}/pve-csi/storageclass-cephfs.yaml"

echo "[*] Waiting for CSI controller to be available..."
"${OC_BIN}" -n csi-proxmox rollout status deployment/proxmox-csi-plugin-controller --timeout=180s || true

echo "=================================================="
echo "== StorageClasses =="
echo "=================================================="
"${OC_BIN}" get storageclass
echo "=================================================="
echo "== Proxmox CSI Pods =="
echo "=================================================="
"${OC_BIN}" -n csi-proxmox get pods -o wide
echo "[✓] Proxmox CSI Plugin deployed successfully!"
