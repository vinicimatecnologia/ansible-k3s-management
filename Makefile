SHELL := /bin/bash

EXTRA ?=
ANSIBLE := ansible-playbook

.PHONY: help status cordon-drain uncordon

help:
	@echo "k3s worker lifecycle"
	@echo ""
	@echo "Operations:"
	@echo "  status         - kubectl get nodes for the worker label"
	@echo "  cordon-drain   - cordon + drain all workers (best-effort, honors PDBs)"
	@echo "  uncordon       - uncordon all workers"
	@echo ""
	@echo "Override worker label / drain options via group_vars/all.yml or:"
	@echo "  make <target> EXTRA='-e worker_label=node-role.kubernetes.io/worker'"
	@echo "  make <target> EXTRA='-e kubeconfig=/etc/rancher/k3s/k3s.yaml'"

status:
	$(ANSIBLE) status.yml $(EXTRA)

cordon-drain:
	$(ANSIBLE) cordon-drain.yml $(EXTRA)

uncordon:
	$(ANSIBLE) uncordon.yml $(EXTRA)
