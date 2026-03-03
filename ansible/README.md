## Prerequisites

### Install Python 3.12 or higher

### Install ansible-core

```bash
python3 -m pip install ansible-core
```

## Run Playbook

```bash
ansible-playbook -i ~/.rostr/generated/ansible-inventory.yaml playbooks/extend_lvm.yaml
```

## Upgrade

See [k3s-ansible](https://github.com/k3s-io/k3s-ansible) for upgrade instructions.

## Install k3s-ansible Collection

```bash
ansible-galaxy collection install git+https://github.com/k3s-io/k3s-ansible.git
```

## Install K3s

Install K3s cluster and download kubeconfig:

```bash
ansible-playbook k3s.orchestration.site -i inventory/inventory.yaml --tags kubeconfig
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
ansible-playbook -i ~/.rostr/generated/ansible-inventory.yaml playbooks/restore_pvcs.yaml
```

#### Post-Restore: Nextcloud File Scan

After restoring Nextcloud PVC data, rescan files to update the database:

```bash
kubectl -n nextcloud exec -it deployment/nextcloud -- /bin/bash -c "php occ files:scan edvinas"
```

This is necessary because the restored files exist on disk, but Nextcloud's database doesn't know about them until the scan completes.

## Uninstall K3s

```bash
ansible-playbook -i ~/.rostr/generated/ansible-inventory.yaml playbooks/uninstall_k3s.yaml
```
