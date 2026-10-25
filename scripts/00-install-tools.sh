#!/usr/bin/env bash
# ==============================================================================
# Script 00: Install OKD / OpenShift Tools (openshift-install, oc, kubectl)
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

OKD_VERSION="${OKD_VERSION:-5.0.0-okd-scos.ec.0}"
BIN_DIR="${REPO_ROOT}/bin"
mkdir -p "${BIN_DIR}"

echo "=================================================="
echo "== Checking / Installing OKD CLI Tools (${OKD_VERSION}) =="
echo "=================================================="

# Check existing installation in PATH or local bin
if command -v openshift-install &>/dev/null && command -v oc &>/dev/null && command -v kubectl &>/dev/null; then
    echo "[✓] OKD tools already installed in system PATH:"
    echo "    openshift-install: $(openshift-install version | head -n 1)"
    echo "    oc:                $(oc version --client | head -n 1)"
    exit 0
fi

if [[ -x "${BIN_DIR}/openshift-install" && -x "${BIN_DIR}/oc" && -x "${BIN_DIR}/kubectl" ]]; then
    echo "[✓] OKD tools found in local ${BIN_DIR}:"
    "${BIN_DIR}/openshift-install" version | head -n 1
    exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "[*] Downloading OKD client and installer packages (${OKD_VERSION})..."
CLIENT_URL="https://github.com/okd-project/okd/releases/download/${OKD_VERSION}/openshift-client-linux-${OKD_VERSION}.tar.gz"
INSTALLER_URL="https://github.com/okd-project/okd/releases/download/${OKD_VERSION}/openshift-install-linux-${OKD_VERSION}.tar.gz"

curl -fsSL "${CLIENT_URL}" -o "${TMP_DIR}/client.tar.gz"
curl -fsSL "${INSTALLER_URL}" -o "${TMP_DIR}/installer.tar.gz"

echo "[*] Extracting binaries..."
tar -xzf "${TMP_DIR}/client.tar.gz" -C "${TMP_DIR}"
tar -xzf "${TMP_DIR}/installer.tar.gz" -C "${TMP_DIR}"

if [[ $EUID -eq 0 && -d "/usr/local/bin" ]]; then
    install -m 0755 "${TMP_DIR}/oc" /usr/local/bin/
    install -m 0755 "${TMP_DIR}/kubectl" /usr/local/bin/
    install -m 0755 "${TMP_DIR}/openshift-install" /usr/local/bin/
    echo "[✓] Successfully installed tools to /usr/local/bin"
else
    install -m 0755 "${TMP_DIR}/oc" "${BIN_DIR}/"
    install -m 0755 "${TMP_DIR}/kubectl" "${BIN_DIR}/"
    install -m 0755 "${TMP_DIR}/openshift-install" "${BIN_DIR}/"
    echo "[✓] Successfully installed tools to ${BIN_DIR}"
    echo "    Add to PATH: export PATH=\"${BIN_DIR}:\${PATH}\""
fi

echo "=================================================="
echo "== Verification =="
echo "=================================================="
openshift-install version || "${BIN_DIR}/openshift-install" version
oc version --client || "${BIN_DIR}/oc" version --client
echo "[✓] OKD Tools Setup Complete!"
