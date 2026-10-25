#!/usr/bin/env bash
# ==============================================================================
# Script 04: Monitor OKD SNO Installation & Complete Initial Setup
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

echo "=================================================="
echo "== Monitoring OKD SNO ${CLUSTER_NAME} Installation =="
echo "=================================================="

INSTALLER_BIN="openshift-install"
if ! command -v "${INSTALLER_BIN}" &>/dev/null; then
    INSTALLER_BIN="${REPO_ROOT}/bin/openshift-install"
fi

OC_BIN="oc"
if ! command -v "${OC_BIN}" &>/dev/null; then
    OC_BIN="${REPO_ROOT}/bin/oc"
fi

echo "[*] Waiting for Agent installer to complete installation..."
echo "    Assets Directory: ${INSTALL_DIR}"
echo "    Node IP:          ${VM_IP}"
echo "    Console URL:      https://console-openshift-console.apps.${CLUSTER_FQDN}"

"${INSTALLER_BIN}" agent wait-for install-complete --dir="${INSTALL_DIR}" --log-level=info

echo "[✓] Installation reported complete!"

if [[ -f "${KUBECONFIG_FILE}" ]]; then
    export KUBECONFIG="${KUBECONFIG_FILE}"
    echo "[✓] Found Kubeconfig: ${KUBECONFIG_FILE}"

    echo "[*] Approving any pending Certificate Signing Requests (CSRs)..."
    PENDING_CSRS=$("${OC_BIN}" get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' || true)
    if [[ -n "${PENDING_CSRS}" ]]; then
        echo "${PENDING_CSRS}" | xargs -r "${OC_BIN}" adm certificate approve || true
        echo "[✓] Approved pending CSRs."
    else
        echo "[✓] No pending CSRs."
    fi

    echo "[*] Configuring In-Cluster Image Registry (emptyDir for initial SNO bootstrap)..."
    "${OC_BIN}" patch configs.imageregistry.operator.openshift.io/cluster --type=merge \
        -p '{"spec":{"managementState":"Managed","storage":{"emptyDir":{}}}}' || true

    echo "=================================================="
    echo "== Cluster Operators Status =="
    echo "=================================================="
    "${OC_BIN}" get clusterversion || true
    "${OC_BIN}" get nodes -o wide || true
    "${OC_BIN}" get co || true
fi

echo "=================================================="
echo "== OKD mickey17 is Online and Ready =="
echo "=================================================="
