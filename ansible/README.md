## Prerequisites

### Install Python 3.12 or higher

### Install ansible-core

```bash
python3 -m pip install ansible-core
```

## Upgrade

See [k3s-ansible](https://github.com/k3s-io/k3s-ansible) for upgrade instructions.

## Install k3s-ansible Collection

```bash
ansible-galaxy collection install git+https://github.com/k3s-io/k3s-ansible.git
```

## Prepare Nodes for K3s

Before installing K3s, prepare your nodes by updating packages, disabling swap, and configuring firewall:

```bash
ansible-playbook -i ~/.rostr/generated/ansible-inventory.yaml playbooks/prepare_k3s.yaml
```

This will:
- Update apt cache and upgrade all Ubuntu packages
- Disable swap immediately and remove from `/etc/fstab`
- Stop and disable firewalld service
- Increase inotify limits
- Stop, disable and mask `multipathd` (required for Longhorn)
- Extend the root LVM logical volume and resize the filesystem

## Install K3s

Install K3s cluster and download kubeconfig:

```bash
ansible-playbook k3s.orchestration.site -i inventory/inventory.yaml --tags kubeconfig
```

## Uninstall K3s

```bash
ansible-playbook -i ~/.rostr/generated/ansible-inventory.yaml playbooks/uninstall_k3s.yaml
```
