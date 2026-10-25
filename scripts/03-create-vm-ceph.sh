#!/usr/bin/env bash
# ==============================================================================
# Script 03: Create OKD Single Node OpenShift VM on Proxmox VE using Ceph Storage
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
REMOTE_ISO_NAME="agent-${CLUSTER_NAME}.iso"

echo "=================================================="
echo "== Creating OKD SNO VM ${VM_ID} (${VM_NAME}) on Ceph =="
echo "=================================================="

# Check if VM already exists on Proxmox
EXISTS=$(ssh "${PVE_SSH}" "qm status ${VM_ID} 2>/dev/null || true")
if [[ -n "${EXISTS}" ]]; then
    echo "[!] Warning: VM ${VM_ID} already exists on Proxmox."
    echo "[*] Stopping and destroying old VM ${VM_ID}..."
    ssh "${PVE_SSH}" bash -s << EOF
qm stop ${VM_ID} 2>/dev/null || true
sleep 3
qm destroy ${VM_ID} --purge 1 2>/dev/null || true
EOF
    echo "[✓] Cleaned up existing VM ${VM_ID}."
fi

# Create VM with Ceph RBD Storage
echo "[*] Provisioning VM ${VM_ID} with Ceph RBD backing..."
ssh "${PVE_SSH}" bash -s << EOF
set -euo pipefail

# 1. Create base VM configuration
qm create ${VM_ID} \
    --name "${VM_NAME}" \
    --memory ${VM_RAM} \
    --cpu host \
    --cores ${VM_CPUS} \
    --numa 0 \
    --ostype l26 \
    --machine q35 \
    --onboot 1

# 2. Configure VirtIO SCSI Single controller
qm set ${VM_ID} --scsihw virtio-scsi-single

# 3. Allocate Root Disk on Ceph RBD (${PVE_STORAGE_CEPH_RBD})
echo "Allocating 100G root disk on Ceph pool: ${PVE_STORAGE_CEPH_RBD}..."
qm set ${VM_ID} --scsi0 ${PVE_STORAGE_CEPH_RBD}:100,discard=on,ssd=1,iothread=1

# 4. Attach Network Device
qm set ${VM_ID} --net0 virtio,bridge=${PVE_BRIDGE},macaddr=${VM_MAC},mtu=1500

# 5. Attach Agent Installer ISO (from ${PVE_STORAGE_ISO})
# Check if ISO exists in cephfs or local
if pvesm list ${PVE_STORAGE_ISO} 2>/dev/null | grep -q "${REMOTE_ISO_NAME}"; then
    ISO_VOL="${PVE_STORAGE_ISO}:iso/${REMOTE_ISO_NAME}"
else
    ISO_VOL="local:iso/${REMOTE_ISO_NAME}"
fi
echo "Attaching installer CD-ROM: \${ISO_VOL}..."
qm set ${VM_ID} --ide2 "\${ISO_VOL}",media=cdrom

# 6. Set Boot Order: CD-ROM first for initial installer run, then Ceph disk
qm set ${VM_ID} --boot order=ide2\;scsi0

# 7. Configure Console, Guest Agent & Homelab Metadata
qm set ${VM_ID} --serial0 socket --vga serial0
qm set ${VM_ID} --agent 1
qm set ${VM_ID} --tags "okd;sno;ceph;poc;mickey17"

# 8. Start the VM
echo "Starting VM ${VM_ID}..."
qm start ${VM_ID}
EOF

echo "[✓] VM ${VM_ID} created and started successfully!"
echo "=================================================="
echo "== VM Specifications =="
echo "=================================================="
ssh "${PVE_SSH}" "qm config ${VM_ID}"
echo "=================================================="
echo "== Ceph RBD Disk Allocation =="
echo "=================================================="
ssh "${PVE_SSH}" "pvesm list ${PVE_STORAGE_CEPH_RBD} | grep 'vm-${VM_ID}'"
echo "[✓] SNO Node is booting from Agent installer ISO onto Ceph storage."
