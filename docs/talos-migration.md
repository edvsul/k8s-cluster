# Migrating the staging cluster from k3s on Ubuntu to Talos Linux

*Plan for [edvsul/k8s-cluster](https://github.com/edvsul/k8s-cluster), revision 2 — October 2026, targeting Talos 1.14.x.*

## 1. Summary

The cluster keeps its shape: one control plane, three workers, all on the same switch and the same `10.0.0.0/24` network, still the `staging` cluster reconciled by Flux from `./clusters/staging`. What changes is the operating system and Kubernetes distribution underneath.

A Talos node can't join a k3s cluster, so this is a rebuild on the same hardware. Data moves across through the Longhorn backups you already ship to S3, and everything else is recreated by Flux from the existing manifests. The migration starts by draining `10.0.0.77` out of k3s and installing Talos on it.

The guiding constraint is to leave the existing code alone. Everything Talos-specific lives in a new `talos/` directory, plus one throwaway folder used only during the pilot. No file under `apps/`, `infrastructure/`, `monitoring/` or `clusters/staging/` has to change. Section 4 explains how the few Talos differences that would normally need manifest changes are absorbed in the Talos machine config instead.

## 2. One consequence of starting with `.77`

A Talos cluster needs a control plane from its very first node, and with a single control plane that node can't be swapped later without rebuilding the cluster. So **`.77` becomes the new control plane and `.78` becomes a worker.** Both are 8 GB 4-core i3 machines, so it is an even swap, and it is the cleanest option: the k3s control plane on `.78` keeps running untouched until cutover.

| Node | Today | After migration |
|---|---|---|
| 10.0.0.77 (OptiPlex 7010, 8 GB) | k3s worker | **Talos control plane** |
| 10.0.0.78 (OptiPlex 9020, 8 GB) | k3s control plane | Talos worker |
| 10.0.0.76 (EliteDesk, 16 GB) | k3s worker | Talos worker |
| 10.0.0.75 (EliteDesk, 16 GB) | k3s worker | Talos worker |

While `.77` is drained, the old cluster runs on `.78` (control plane) and the two 16 GB workers, which is more headroom than if one of those had gone first. Longhorn's two replicas per volume still fit on two workers.

## 3. Same switch, two clusters

Keeping `.77` on the same switch is fine. Talos gets the same static address `10.0.0.77/24`, and the two clusters simply share the LAN for a while. Only four things can collide on a shared network, and each is avoided without touching the repo.

The Cilium ingress VIP `10.0.0.240` must be announced by only one cluster. The IP pool, the L2 policy and the ingress annotation are not in Git today (they come from `install_cilium.yaml`), so the Talos bootstrap simply uses a temporary pool, `10.0.0.230–10.0.0.235` with the ingress on `.230`, and switches to `.240–.250` at cutover.

The Cloudflare tunnel credentials are shared, so cloudflared must never run in both clusters. It is part of `apps`, which the pilot doesn't deploy.

The Tailscale operator and the `home-subnet-router` Connector would register duplicate devices, and Renovate would open duplicate PRs. The pilot drops both (see §5).

Longhorn on both clusters points at the same S3 bucket. That is what makes restoring possible, but the pilot must not run the `default` RecurringJob, so it is dropped as well.

## 4. Absorbing Talos differences without changing manifests

**Pod Security.** Talos enforces the `baseline` Pod Security Standard on all namespaces except `kube-system` by default, which would block Longhorn and node-exporter unless their namespaces are labelled. k3s doesn't enforce PSA, and your Kyverno policy already enforces the restricted profile on app namespaces, with exclusions for exactly the infrastructure namespaces. So the Talos config sets the cluster-wide PSA default to `enforce: privileged` (keeping `audit`/`warn: restricted`). That reproduces today's behaviour with no namespace changes, and Kyverno remains the policy layer.

**Longhorn data path.** Talos 1.14 removed kubelet `extraMounts`, so the old `/var/lib/longhorn` bind mount isn't possible. Instead, a `UserVolumeConfig` named `longhorn` with `volumeType: directory` creates `/var/mnt/longhorn` on the `EPHEMERAL` partition. That partition takes the rest of the disk by default, just as the root LV does today, and user volumes are shared into the kubelet without extra mounts. Longhorn's `defaultDataPath` has to point there. That one value is the only manifest difference. The pilot overlay sets it as a HelmRelease patch, and at cutover it moves into `infrastructure/controllers/base/longhorn/release.yaml`, after the k3s nodes are gone. Talos preserves `EPHEMERAL` across upgrades. The things to avoid are `talosctl reset` without `--system-labels-to-wipe STATE` and the old `--preserve=false` upgrade flag.

**k3s server flags.** `--flannel-backend=none`, `--disable-kube-proxy`, `--disable=traefik,servicelb` and the control-plane `NoSchedule` taint map to `cni: none`, `proxy.disabled: true`, nothing (Talos ships neither traefik nor servicelb) and Talos's default control-plane taint.

**Node preparation playbooks.** Swap and firewalld don't exist on Talos. `multipathd` isn't present. The NFS client for Longhorn RWX (Nextcloud) is in the kernel. The inotify sysctls go into `machine.sysctls`, and the image GC thresholds into `machine.kubelet.extraConfig`. Longhorn's `iscsi-tools` and `util-linux-tools` come as system extensions baked into the image.

**The backup credentials Secret.** The `longhorn-backup-s3` Secret is created by the existing Terraform via the kubernetes provider. Point it at the new cluster with `terraform apply -var kubeconfig_path=<talos kubeconfig>` and the provider recreates the Secret there. No code change is needed.

**Remote `kubectl`.** The host-level `tailscaled` on `.78` is replaced by the `siderolabs/tailscale` system extension on `.77`, configured through an `ExtensionServiceConfig`. The node's tailnet name goes into the API server `certSANs`.

## 5. What gets added to the repo

```
talos/                              # NEW — everything Talos-specific
  talconfig.yaml                    # talhelper: cluster + 4 nodes, versions, patches
  talsecret.sops.yaml               # Talos PKI, encrypted with your existing age key
  schematic.yaml                    # Image Factory extensions
  patches/
    common.yaml                     # sysctls, kubelet GC + Longhorn mount, cni none, PSA
    controlplane.yaml               # tailscale extension config, metrics bind addresses
  cilium-values.yaml                # your current values + Talos settings
  cilium-lb.yaml.tpl                # lan-pool + lan-l2, range filled in by the script
  Taskfile.yaml                     # single entry point for every step below
  scripts/
    longhorn-evict-node.sh
    longhorn-backup-all.sh
    longhorn-restore-all.sh
ansible/playbooks/kexec_to_talos.yaml   # NEW — boots an Ubuntu host into Talos
clusters/talos-pilot/               # TEMPORARY — deleted at cutover
```

For generating machine configs, `talhelper` is a better fit than a Terraform root. It is a single YAML file plus SOPS-encrypted secrets, both of which match how the repo already works. It produces plain configs that `talosctl` applies, and it adds no new state to manage.

Cilium stays outside Flux, as it is today. `talos/cilium-values.yaml` is your values block from `install_cilium.yaml` with these Talos additions:

```yaml
k8sServiceHost: localhost
k8sServicePort: 7445                # KubePrism on every Talos node
cgroup:
  autoMount: { enabled: false }
  hostRoot: /sys/fs/cgroup
securityContext:
  capabilities:
    ciliumAgent: [CHOWN, KILL, NET_ADMIN, NET_RAW, IPC_LOCK, SYS_ADMIN, SYS_RESOURCE, DAC_OVERRIDE, FOWNER, SETGID, SETUID]
    cleanCiliumState: [NET_ADMIN, SYS_ADMIN, SYS_RESOURCE]
ingressController:
  service:
    annotations:
      io.cilium/lb-ipam-ips: "${INGRESS_VIP}"   # .230 during the pilot, .240 after cutover
devices: "eno+"                     # confirm with `talosctl get links` on .77
```

The `devices` restriction matters even more with the Tailscale extension on the host, because otherwise Cilium also picks up `tailscale0`.

**The temporary pilot folder** lets the new cluster run your real infrastructure manifests before cutover without deploying the parts that would collide. It holds a `flux-system/` directory written by `flux bootstrap`, plus one file, `infrastructure.yaml`. That file is a copy of `clusters/staging/infrastructure.yaml` with the **same Kustomization names and paths**, extended with `$patch: delete` patches that drop the Tailscale HelmRelease and Connector, the Renovate CronJob and the Longhorn RecurringJob:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure-controllers        # same name as in clusters/staging
  namespace: flux-system
spec:
  path: ./infrastructure/controllers/staging
  # ...interval, sourceRef, prune, decryption identical to staging...
  patches:
    - patch: |
        $patch: delete
        apiVersion: helm.toolkit.fluxcd.io/v2
        kind: HelmRelease
        metadata: { name: tailscale-operator, namespace: kube-system }
    - patch: |
        $patch: delete
        apiVersion: batch/v1
        kind: CronJob
        metadata: { name: renovate, namespace: renovate }
# infrastructure-configs: same idea, deleting the Connector and the RecurringJob
```

Check the exact resource names against `kustomize build` when you write it. The identical Kustomization names are important. At cutover, Flux is re-pointed to `./clusters/staging`, the same objects are simply updated (the patches disappear and Tailscale and Renovate appear), and nothing gets pruned and recreated.

## 6. The automation pieces

**`kexec_to_talos.yaml`** runs against a single Ubuntu host. It downloads the Talos kernel, initramfs and kernel command line for your schematic from Image Factory, appends `ip=<node-ip>::10.0.0.1:255.255.255.0` so the node keeps its address, and kexecs into it. The host comes back in Talos maintenance mode (in RAM, disk untouched) listening on port 50000, and the playbook waits for that port. The disk is only wiped when the config with `install.wipe: true` is applied. If kexec misbehaves on one of these older boards, boot the factory ISO for the same schematic from USB. That is the only manual fallback anywhere in the plan.

**`longhorn-evict-node.sh <node>`** cordons and drains the node. It sets `allowScheduling: false` and `evictionRequested: true` on its `nodes.longhorn.io` object, waits until no Longhorn replica references the node, then deletes the Kubernetes node.

**`longhorn-backup-all.sh`** triggers a backup of every volume and waits until all of them complete.

**`longhorn-restore-all.sh`** runs on the new cluster. For each backup volume in S3, it reads the latest backup and the original PV, PVC and namespace that Longhorn records with every backup. It then creates a Longhorn `Volume` with `spec.fromBackup`, waits for the restore, and creates a static PV and a PVC with the original names (`rwx` for Nextcloud's data). When Flux then creates the StatefulSets and Deployments, they bind to the restored data instead of provisioning empty volumes. A skip list covers volumes not worth restoring, such as Prometheus's 7-day TSDB.

**`talos/Taskfile.yaml`** wraps it all:

| Task | What it does |
|---|---|
| `task evict NODE=…` | Runs the eviction script against the **k3s** context |
| `task kexec NODE=…` | Ansible playbook above |
| `task genconfig` | `talhelper genconfig` (decrypts `talsecret` with your age key) |
| `task apply NODE=…` | `talosctl apply-config --insecure` for a node in maintenance mode |
| `task bootstrap` | `talosctl bootstrap`, fetch kubeconfig, `helm install cilium`, apply the LB pool and L2 policy, create `sops-age`, run Terraform for the S3 Secret |
| `task cilium VIP=…` | `helm upgrade` Cilium and re-apply the pool with the given range |
| `task flux PATH=…` | `flux bootstrap github … --path=$PATH` (your README command) |
| `task backup` / `task restore` | The Longhorn scripts |
| `task health` | `talosctl health`, `flux check`, Longhorn pods ready |

## 7. Phases

### Phase 0 — Prepare (no impact)

Write the `talos/` directory, the playbook and the pilot folder, and merge them. Nothing existing is touched, so the k3s cluster is unaffected. Validate offline with `talhelper genconfig`, `talosctl validate --mode metal` and `kustomize build` on the pilot overlay.

Confirm in the Longhorn UI that every volume has a recent successful backup. Take independent copies as insurance: `pg_dump` of the linkding and Firefly III databases, a `mariadb-dump` of Nextcloud, and the Uptime Kuma data. Store the age key safely.

### Phase 1 — Drain `.77` and install Talos (no downtime)

1. `task evict NODE=10.0.0.77`, then wait for Longhorn to rebuild replicas on `.75` and `.76`. Check that their disks have room for all replicas before you start.
2. `task kexec NODE=10.0.0.77`. In maintenance mode, run `talosctl get disks --insecure` and `get links --insecure` to confirm the install disk and the NIC name.
3. `task genconfig && task apply NODE=10.0.0.77 && task bootstrap`. For the pilot, `.77` has `allowSchedulingOnControlPlanes: true`, because it is the only node, and Cilium uses the `.230` range.
4. `task flux PATH=./clusters/talos-pilot`. Flux deploys cert-manager, Kyverno, Longhorn, goldpinger, reflector and the Cilium configs from your existing manifests. Longhorn shows volumes as degraded on one node, which is expected.

### Phase 2 — Restore rehearsal (no downtime)

Restore linkding's two volumes on the new cluster and check the data through a port-forward. One way to run linkding there without its cloudflared is a temporary extra Kustomization in the pilot folder pointing at `./apps/base/linkding`. Also time the restore of one larger volume, so you can size the cutover window, since Nextcloud's 40 GiB dominates it. This phase shakes out the restore script and any Talos surprises. Afterwards, delete the rehearsal workloads and volumes from the new cluster. The old cluster stays live throughout.

### Phase 3 — Cutover (planned window, roughly 1–3 hours of downtime)

1. **Freeze the old cluster.** Turn on Nextcloud maintenance mode. Run `flux suspend kustomization --all` on k3s, then scale the apps and cloudflared to zero. Run `task backup` against k3s and wait for it to finish, then suspend the RecurringJob. Scale the Tailscale operator to zero and delete the old `k8s-home-subnet-router` device in the Tailscale console.
2. **Wipe the rest.** Copy `/var/lib/rancher/k3s/server/db` and `token` from `.78` to your laptop. This is the point of no return. Then run `task kexec` and `task apply` for `.78`, `.76` and `.75` as workers. Because the old Cilium is gone with them, `.240` is now free.
3. **Return `.77` to a dedicated control plane.** Set `allowSchedulingOnControlPlanes: false` and re-apply. Drain and uncordon `.77` so pilot workloads move to the workers, and disable Longhorn scheduling on it, so storage lives on the three workers exactly as today.
4. **Switch the VIP.** `task cilium VIP=10.0.0.240` moves the pool to `.240–.250`.
5. **Restore data.** `task restore`.
6. **Hand over to the normal staging path.** `task flux PATH=./clusters/staging`. Flux re-points to the same path as today and adopts the infrastructure Kustomizations. Tailscale, Renovate and the RecurringJob appear, and monitoring and apps deploy onto the restored PVCs. cloudflared reconnects the tunnel, and the Connector re-advertises `10.0.0.240/28`.
7. **Verify** the public and VPN-only endpoints, then turn off Nextcloud maintenance mode. Trigger one manual Longhorn backup and check that it lands in S3.

Until step 2, rolling back means resuming Flux on k3s and scaling the apps back up. After step 2, recovery relies on S3 plus the Phase 0 dumps, both of which Phase 2 has already proven.

### Phase 4 — Clean up (no impact)

Delete `clusters/talos-pilot/`. Optionally remove the k3s playbooks (`prepare_k3s`, `configure_image_gc`, `install_cilium`, `uninstall_k3s`) and update the README's OS column and install instructions. Two small follow-ups:

- The `chaos` skill expects the `k3s-ansible` kube context and uses SSH for host-level faults. You can rename the Talos context to `k3s-ansible` in your kubeconfig to keep it working, but the SSH-based faults need `talosctl` equivalents.
- kube-prometheus-stack will scrape Talos's etcd, scheduler and controller-manager once `patches/controlplane.yaml` sets their metrics bind addresses to `0.0.0.0`. That is a Talos config change, not a repo change.

For future Talos upgrades, `talosctl upgrade` per node (control plane first) with the installer image from your schematic is enough at this size. Renovate can bump the Talos version in `talconfig.yaml` if you add a regex manager.

## 8. Risks

| Risk | Mitigation |
|---|---|
| A restore from S3 fails or is incomplete | Rehearsed in Phase 2; database dumps from Phase 0; S3 versioning on the bucket |
| kexec doesn't work on an older board | USB stick with the same schematic's ISO |
| Old cluster tight on disk while `.77` is out | Check Longhorn disk headroom on `.75`/`.76` before evicting |
| Cilium `devices: eno+` doesn't match Talos's NIC name | Checked in maintenance mode on `.77` before bootstrap |
| Both clusters announce the same IP on the shared switch | Pilot uses `.230–.235`; `.240` moves only after the old nodes are wiped |
| Losing remote access during the window | Do the cutover from the LAN; the Tailscale extension on `.77` restores remote `kubectl`/`talosctl` independently of the in-cluster subnet router |
