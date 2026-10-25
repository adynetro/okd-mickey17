.PHONY: all help tools prep iso vm wait csi test clean destroy

SHELL := /usr/bin/env bash

help:
	@echo "======================================================================="
	@echo "  OKD Single Node OpenShift (SNO / AIO) Installer: mickey17"
	@echo "  Proxmox VE + Ceph Storage + Proxmox CSI Plugin"
	@echo "======================================================================="
	@echo "Targets:"
	@echo "  make tools    - Download / verify openshift-install and oc CLI tools"
	@echo "  make prep     - Verify Ceph storage and configure Proxmox CSI RBAC"
	@echo "  make iso      - Generate the bootable Agent Installer ISO and upload to Ceph"
	@echo "  make vm       - Create and boot the SNO VM (VMID 117) on Ceph RBD"
	@echo "  make wait     - Wait for SNO installation to finish and approve CSRs"
	@echo "  make csi      - Deploy Proxmox CSI plugin and Ceph StorageClasses"
	@echo "  make test     - Run end-to-end dynamic Ceph RBD PVC test pod"
	@echo "  make deploy   - Full end-to-end deployment (prep -> iso -> vm -> wait -> csi -> test)"
	@echo "  make destroy  - Teardown VM 117 and purge Ceph RBD disk"
	@echo "======================================================================="

tools:
	@./scripts/00-install-tools.sh

prep:
	@./scripts/01-prep-proxmox-ceph.sh

iso:
	@./scripts/02-generate-iso.sh

vm:
	@./scripts/03-create-vm-ceph.sh

wait:
	@./scripts/04-wait-for-install.sh

csi:
	@./scripts/05-deploy-proxmox-csi.sh

test:
	@./scripts/06-test-ceph-storage.sh

destroy:
	@./scripts/destroy-vm.sh

deploy: prep iso vm wait csi test
	@echo "[✓] mickey17 OKD cluster deployed successfully with Ceph backing and Proxmox CSI!"
