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

## Prepare Nodes for K3s

Before installing K3s, prepare your nodes by updating packages, disabling swap, and configuring firewall:

```bash
ansible-playbook -i ~/.rostr/generated/ansible-inventory.yaml playbooks/prepare_k3s.yaml
```

This will:
- Update apt cache and upgrade all Ubuntu packages
- Disable swap immediately and remove from `/etc/fstab`
- Stop and disable firewalld service

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

### Restore PVCs to Longhorn Volumes

After installing a new K3s cluster, bootstrapping Flux, and deploying applications with Longhorn storage, restore your PVCs manually using temporary pods:

#### 1. Scale Down Applications

```bash
# Scale down the application to release the PVC
kubectl scale deployment <app-name> -n <namespace> --replicas=0

# For StatefulSets (e.g., MariaDB)
kubectl scale statefulset <statefulset-name> -n <namespace> --replicas=0
```

#### 2. Create Temporary Restore Pod

```bash
kubectl run <app-name>-restore \
  -n <namespace> \
  --image=ubuntu:22.04 \
  --restart=Never \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "restore",
        "image": "ubuntu:22.04",
        "command": ["sleep", "3600"],
        "volumeMounts": [{
          "name": "data",
          "mountPath": "/restore"
        }]
      }],
      "volumes": [{
        "name": "data",
        "persistentVolumeClaim": {
          "claimName": "<pvc-name>"
        }
      }]
    }
  }'
```

#### 3. Wait for Pod to be Ready

```bash
kubectl wait --for=condition=Ready pod/<app-name>-restore -n <namespace> --timeout=120s
```

#### 4. Copy and Extract Backup

```bash
# Copy backup to pod
kubectl cp ../k3s-backups/<node>/pvc-<uuid>_<namespace>_<pvc-name>_<timestamp>.tar.gz \
  <namespace>/<app-name>-restore:/tmp/backup.tar.gz

# Extract inside the pod
kubectl exec -n <namespace> <app-name>-restore -- tar -xzf /tmp/backup.tar.gz -C /restore

# Verify data
kubectl exec -n <namespace> <app-name>-restore -- ls -la /restore
```

#### 5. Cleanup and Scale Up

```bash
# Delete restore pod
kubectl delete pod <app-name>-restore -n <namespace>

# Scale application back up
kubectl scale deployment <app-name> -n <namespace> --replicas=1
```

**Note:** The mount path `/restore` is arbitrary. The important part is that the temporary pod mounts the same PVC that the application uses. Longhorn automatically replicates the data across nodes as you extract it.

#### Post-Restore: Nextcloud File Scan

After restoring Nextcloud PVC data, rescan files to update the database:

```bash
kubectl -n nextcloud exec -it deployment/nextcloud -- /bin/bash -c "php occ files:scan edvinas"
```

## Uninstall K3s

```bash
ansible-playbook -i ~/.rostr/generated/ansible-inventory.yaml playbooks/uninstall_k3s.yaml
```
