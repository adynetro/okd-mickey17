#!/usr/bin/env bash
# ==============================================================================
# Script 01: Prepare Proxmox VE & Ceph Storage for OKD mickey17
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
echo "== Preparing Proxmox VE & Ceph Cluster (${PVE_HOST}) =="
echo "=================================================="

# 1. Test SSH connectivity
echo "[*] Checking SSH connection to Proxmox node ${PVE_HOST}..."
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "${PVE_SSH}" "uptime" >/dev/null 2>&1; then
    echo "[!] Error: Unable to SSH into ${PVE_SSH}. Ensure passwordless SSH key authentication is configured."
    exit 1
fi
echo "[✓] SSH connection confirmed."

# 2. Check Ceph cluster health
echo "[*] Checking Ceph cluster health..."
ssh "${PVE_SSH}" "ceph status"

# 3. Verify Ceph RBD and CephFS storage pools
echo "[*] Verifying Proxmox storage pools..."
PVE_STORAGES=$(ssh "${PVE_SSH}" "pvesm status")
echo "${PVE_STORAGES}"

if ! echo "${PVE_STORAGES}" | grep -q "${PVE_STORAGE_CEPH_RBD}"; then
    echo "[!] Error: Storage pool '${PVE_STORAGE_CEPH_RBD}' not found in Proxmox storage list!"
    exit 1
fi
echo "[✓] Ceph RBD pool '${PVE_STORAGE_CEPH_RBD}' confirmed active."

if ! echo "${PVE_STORAGES}" | grep -q "${PVE_STORAGE_ISO}"; then
    echo "[!] Warning: ISO storage pool '${PVE_STORAGE_ISO}' not found. Defaulting to local."
    PVE_STORAGE_ISO="local"
fi
echo "[✓] ISO storage pool set to '${PVE_STORAGE_ISO}'."

# 4. Configure Proxmox CSI Role, User & API Token
echo "[*] Configuring Proxmox CSI RBAC and API token..."
TOKEN_OUTPUT=$(ssh "${PVE_SSH}" bash -s << 'EOF'
set -euo pipefail

# 1. Create CSI Role if not present
if ! pveum role list --output-format json | grep -q '"roleid":"CSI"'; then
    echo "Creating CSI role..."
    pveum role add CSI -privs "Datastore.Allocate Datastore.AllocateSpace Datastore.Audit VM.Audit VM.Config.Disk"
fi

# 2. Create CSI User if not present
if ! pveum user list --output-format json | grep -q '"userid":"kubernetes-csi@pve"'; then
    echo "Creating kubernetes-csi@pve user..."
    pveum user add kubernetes-csi@pve --comment "Kubernetes CSI Plugin"
fi

# 3. Create or rotate token
if ! pveum user token list kubernetes-csi@pve --output-format json 2>/dev/null | grep -q '"tokenid":"csi"'; then
    echo "Generating new CSI API token..."
    pveum user token add kubernetes-csi@pve csi --privsep 0 --output-format json
else
    echo "Existing token found, rotating to ensure known secret..."
    pveum user token delete kubernetes-csi@pve csi 2>/dev/null || true
    pveum user token add kubernetes-csi@pve csi --privsep 0 --output-format json
fi

# 4. Ensure ACL assigned
pveum acl modify / -user kubernetes-csi@pve -role CSI
EOF
)

# Extract token secret
TOKEN_SECRET=$(echo "${TOKEN_OUTPUT}" | grep -o '"value": *"[^"]*"' | cut -d'"' -f4 || true)
if [[ -z "${TOKEN_SECRET}" ]]; then
    # Fallback to existing configured secret if token wasn't regenerated
    TOKEN_SECRET="${CSI_TOKEN_SECRET:-}"
fi

if [[ -z "${TOKEN_SECRET}" ]]; then
    echo "[!] Error: Could not determine CSI token secret."
    exit 1
fi

echo "[✓] Proxmox CSI Token generated / verified."
echo "    Token ID:     ${CSI_TOKEN_ID}"
echo "    Token Secret: ${TOKEN_SECRET:0:8}..."

# 5. Write pve-csi/config.yaml
mkdir -p "${REPO_ROOT}/pve-csi"
cat << EOF > "${REPO_ROOT}/pve-csi/config.yaml"
# Proxmox CSI Plugin configuration generated for cluster: ${CLUSTER_NAME}
clusters:
  - url: https://${PVE_HOST}:8006/api2/json
    insecure: true
    token_id: "${CSI_TOKEN_ID}"
    token_secret: "${TOKEN_SECRET}"
    region: "${CLUSTER_NAME}"
EOF
chmod 0600 "${REPO_ROOT}/pve-csi/config.yaml"

echo "[✓] CSI configuration written to ${REPO_ROOT}/pve-csi/config.yaml"
echo "=================================================="
echo "== Proxmox VE & Ceph Preparation Complete =="
echo "=================================================="
