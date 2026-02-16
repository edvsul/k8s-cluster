## Prerequisites

### Install python3.12 >=

### Install ansible-core
python3 -m pip install ansible-core

## Run playbook

```bash
ansible-playbook -i ~/.rostr/generated/ansible-inventory.yaml playbooks/extend_lvm.yaml
```

## Upgrade

https://github.com/k3s-io/k3s-ansible

## Install k3s-ansible collection

```bash
ansible-galaxy collection install git+https://github.com/k3s-io/k3s-ansible.git
```

## Backup and Restore PVCs

### Backup PVCs Before Uninstalling K3s

Before uninstalling K3s, backup all local-path PVCs:

```bash
ansible-playbook -i ~/.rostr/generated/ansible-inventory.yaml playbooks/backup_pvcs.yaml
```

This will:
- Find all PVCs on each node
- Create compressed backups in `/backup/k3s-pvcs/` on each node
- Download backups to `../k3s-backups/` (at repository root)
- Export PVC/PV mappings

**Note:** Kubernetes manifests are not backed up since they're managed via GitOps in your Git repository.

Backups are stored in:
```
../k3s-backups/
├── master/
│   ├── pvc-xxxxx_<timestamp>.tar.gz
│   └── pvc-yyyyy_<timestamp>.tar.gz
├── slave/
│   ├── pvc-zzzzz_<timestamp>.tar.gz
│   └── ...
└── pvc-mapping.yaml
```

### Restore PVCs to New K3s Cluster

After installing a new K3s cluster and bootstrapping Flux, restore your PVCs:

```bash
ansible-playbook -i ~/.rostr/generated/ansible-inventory.yaml playbooks/restore_pvcs.yaml -e "namespace=nextcloud"
```

## Uninstall k3s

```bash
ansible-playbook -i ~/.rostr/generated/ansible-inventory.yaml playbooks/uninstall_k3s.yaml
```
