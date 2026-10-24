# Migrating the staging cluster from k3s on Ubuntu to Talos Linux

*Plan for [edvsul/k8s-cluster](https://github.com/edvsul/k8s-cluster), revision 2 — October 2026, targeting Talos 1.14.x.*

## 1. Summary

The cluster keeps its shape: one control plane, three workers, all on the same switch and the same `10.0.0.0/24` network, still the `staging` cluster reconciled by Flux from `./clusters/staging`. What changes is the operating system and Kubernetes distribution underneath.

A Talos node can't join a k3s cluster, so this is a rebuild on the same hardware. Data moves across through the Longhorn backups you already ship to S3, and everything else is recreated by Flux from the existing manifests. The migration starts by draining `10.0.0.77` out of k3s and installing Talos on it under a new address, `10.0.0.81`.

The guiding constraint is to leave the existing code alone. Everything Talos-specific lives in a new `talos/` directory, plus one throwaway folder used only during the pilot. No file under `apps/`, `infrastructure/`, `monitoring/` or `clusters/staging/` has to change. Section 4 explains how the few Talos differences that would normally need manifest changes are absorbed in the Talos machine config instead.

## 2. One consequence of starting with `.77`

A Talos cluster needs a control plane from its very first node, and with a single control plane that node can't be swapped later without rebuilding the cluster. So **`.77` becomes the new control plane (re-addressed to `.81`) and `.78` becomes a worker.** Both are 8 GB 4-core i3 machines, so it is an even swap, and it is the cleanest option: the k3s control plane on `.78` keeps running untouched until cutover.

| Node | Today | After migration |
|---|---|---|
| 10.0.0.77 (OptiPlex 7010, 8 GB) | k3s worker | **Talos control plane, at 10.0.0.81** |
| 10.0.0.78 (OptiPlex 9020, 8 GB) | k3s control plane | Talos worker |
| 10.0.0.76 (EliteDesk, 16 GB) | k3s worker | **Talos worker-1, at 10.0.0.82** (joins during the pilot) |
| 10.0.0.75 (EliteDesk, 16 GB) | k3s worker | Talos worker |

While `.77` is drained, the old cluster runs on `.78` (control plane) and the two 16 GB workers, which is more headroom than if one of those had gone first. Longhorn's two replicas per volume still fit on two workers.

## 3. Same switch, two clusters

Keeping the machine on the same switch is fine. Talos gives it a new static address, `10.0.0.81/24` (set in `talos/patches/control-plane.yaml`), so nothing is confused by the old k3s node object for `.77`, and the two clusters simply share the LAN for a while. Only four things can collide on a shared network, and each is avoided without touching the repo.

The Cilium ingress VIP `10.0.0.240` must be announced by only one cluster. The IP pool, the L2 policy and the ingress annotation are not in Git today (they come from `install_cilium.yaml`), so the Talos bootstrap simply uses a temporary pool, `10.0.0.230–10.0.0.235` with the ingress on `.230`, and switches to `.240–.250` at cutover.

The Cloudflare tunnel credentials are shared, so cloudflared must never run in both clusters. It is part of `apps`, which the pilot doesn't deploy.

The Tailscale operator and the `home-subnet-router` Connector would register duplicate devices, and Renovate would open duplicate PRs. The pilot drops both (see §5).

Longhorn on both clusters points at the same S3 bucket. That is what makes restoring possible, but the pilot must not run the `default` RecurringJob, so it is dropped as well.

## 4. Absorbing Talos differences without changing manifests

**Pod Security.** Talos enforces the `baseline` Pod Security Standard on all namespaces except `kube-system` by default, which would block Longhorn and node-exporter unless their namespaces are labelled. k3s doesn't enforce PSA, and your Kyverno policy already enforces the restricted profile on app namespaces, with exclusions for exactly the infrastructure namespaces. So the Talos config sets the cluster-wide PSA default to `enforce: privileged` (keeping `audit`/`warn: restricted`). That reproduces today's behaviour with no namespace changes, and Kyverno remains the policy layer.

**Longhorn data path.** Talos 1.14 removed kubelet `extraMounts`, so the old `/var/lib/longhorn` bind mount isn't possible. Instead, a `UserVolumeConfig` named `longhorn` with `volumeType: directory` creates `/var/mnt/longhorn` on the `EPHEMERAL` partition. That partition takes the rest of the disk by default, just as the root LV does today, and user volumes are shared into the kubelet without extra mounts. Longhorn's `defaultDataPath` has to point there. That one value is the only manifest difference. The pilot overlay sets it as a HelmRelease patch, and at cutover it moves into `infrastructure/controllers/base/longhorn/release.yaml`, after the k3s nodes are gone. Talos preserves `EPHEMERAL` across upgrades. The things to avoid are `talosctl reset` without `--system-labels-to-wipe STATE` and the old `--preserve=false` upgrade flag.

**k3s server flags.** `--flannel-backend=none`, `--disable-kube-proxy`, `--disable=traefik,servicelb` and the control-plane `NoSchedule` taint map to `cni: none`, `proxy.disabled: true`, nothing (Talos ships neither traefik nor servicelb) and Talos's default control-plane taint.

**Node preparation playbooks.** Swap and firewalld don't exist on Talos. `multipathd` isn't present. The NFS client for Longhorn RWX (Nextcloud) is in the kernel. The inotify sysctls go into `machine.sysctls`, and the image GC thresholds into the `config` field of the `KubeletConfig` document (Talos 1.14 rejects the old `machine.kubelet.extraConfig` once that document exists). Longhorn's `iscsi-tools` and `util-linux-tools` come as system extensions baked into the image.

**The backup credentials Secret.** The `longhorn-backup-s3` Secret is created by the existing Terraform via the kubernetes provider. Point it at the new cluster with `terraform apply -var kubeconfig_path=<talos kubeconfig>` and the provider recreates the Secret there. No code change is needed.

**Remote `kubectl`.** The host-level `tailscaled` on `.78` is replaced by the `siderolabs/tailscale` system extension on the control plane (`.81`), configured through an `ExtensionServiceConfig`. The node's tailnet name goes into the API server `certSANs`.

## 5. What gets added to the repo

```
talos/                              # NEW — everything Talos-specific
  secrets.sops.yaml                 # Talos PKI from `talosctl gen secrets`, encrypted with your existing age key
  schematic.yaml                    # Image Factory extensions (iscsi-tools, util-linux-tools)
  .gitignore                        # keeps generated configs, talosconfig and kubeconfig out of Git
  patches/
    common.yaml                     # every node: DNS, cni none, installer image + disk,
                                    # Longhorn UserVolumeConfig
    control-plane.yaml              # 10.0.0.81 + hostname, no kube-proxy, PSA,
                                    # control-plane taint removed (pilot only)
    worker-1.yaml                   # 10.0.0.82 + hostname (ex-.76)
  cilium/
    cilium-values.yaml              # your current values + Talos settings
    cilium-lb.yaml                  # lan-pool + lan-l2, pilot range .230–.235
  # generated, git-ignored: controlplane.yaml, worker.yaml, talosconfig, kubeconfig
clusters/talos-pilot/               # TEMPORARY — deleted at cutover
```

Machine configs are generated with plain `talosctl`, with no extra tool and no new state. The PKI lives in `secrets.sops.yaml`, encrypted with the same age key as the rest of the repo. You decrypt it to a git-ignored `secrets.yaml` and generate from it:

```bash
sops -d talos/secrets.sops.yaml > talos/secrets.yaml
talosctl gen config talos-cluster https://10.0.0.81:6443 \
  --with-secrets talos/secrets.yaml \
  --config-patch @talos/patches/common.yaml \
  --config-patch-control-plane @talos/patches/control-plane.yaml \
  --config-patch-worker @talos/patches/worker-1.yaml \
  --output-types controlplane,worker \
  --output-dir talos --force             # output-types: keep the existing talosconfig
```

Still to add to the patches: the inotify sysctls and image-GC thresholds from §4, the Tailscale `ExtensionServiceConfig` and API server `certSANs`, and the control-plane metrics bind addresses.

Static IPs and hostnames are per node, so they live in `control-plane.yaml` and `worker-1.yaml`, not in `common.yaml`. `KubeProxyConfig` and `KubeAdmissionControlConfig` are also in `control-plane.yaml`, because `talosctl validate` rejects them on workers. With one worker, `--config-patch-worker` is enough. When `.78` and `.75` join at cutover, generate the worker config without a worker patch and give each node its own patch when applying it: `talosctl apply-config --insecure -n <ip> --file talos/worker.yaml --config-patch @talos/patches/worker-2.yaml`.

Cilium stays outside Flux, as it is today. `talos/cilium/cilium-values.yaml` is your values block from `install_cilium.yaml` with these Talos additions:

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
      io.cilium/lb-ipam-ips: "10.0.0.230"       # pilot; change to 10.0.0.240 at cutover
devices: "eno+"                     # confirm with `talosctl get links` on .81
```

The `devices` restriction matters even more with the Tailscale extension on the host, because otherwise Cilium also picks up `tailscale0`.

**The temporary pilot folder** lets the new cluster run your real infrastructure manifests before cutover without deploying the parts that would collide. It holds a `flux-system/` directory written by `flux bootstrap`, plus one file, `infrastructure.yaml`. That file is a copy of `clusters/staging/infrastructure.yaml` with the **same Kustomization names and paths**, extended with `$patch: delete` patches that drop the Tailscale HelmRelease and Connector, the Renovate CronJob and the Longhorn RecurringJob, plus one strategic-merge patch that sets Longhorn's `defaultDataPath` to `/var/mnt/longhorn`:

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

The patch targets have been checked against `kubectl kustomize infrastructure/controllers/staging` and `infrastructure/configs/staging`: all five names and namespaces match. Re-check if any of those resources is renamed. The other objects in those trees stay, including the SOPS-encrypted Tailscale and Renovate Secrets, which is why `infrastructure-controllers` still needs `sops-age`. The identical Kustomization names are important. At cutover, Flux is re-pointed to `./clusters/staging`, the same objects are simply updated (the patches disappear and Tailscale and Renovate appear), and nothing gets pruned and recreated.

## 6. Manual procedures

Every step is run by hand. There are no scripts, no Taskfile and no kexec playbook. The phases in §7 refer to these procedures by name.

**Evict a k3s node** (against the k3s context). Cordon and drain it, then tell Longhorn to move its replicas off:

```bash
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
kubectl -n longhorn-system patch nodes.longhorn.io <node> --type merge \
  -p '{"spec":{"allowScheduling":false,"evictionRequested":true}}'
kubectl -n longhorn-system get replicas.longhorn.io -l longhornnode=<node>   # repeat until empty
kubectl delete node <node>
```

**Install Talos on a node.** Boot the Image Factory ISO for the schematic (`talos/schematic.yaml`) from USB. The node comes up in maintenance mode (in RAM, disk untouched) on port 50000. Confirm the install disk and the NIC name, then apply the config. The disk is only written when the config is applied.

```bash
talosctl get disks --insecure -n <maintenance-ip>
talosctl get links --insecure -n <maintenance-ip>
talosctl apply-config --insecure -n <maintenance-ip> --file talos/controlplane.yaml   # or worker.yaml
```

**Bootstrap the cluster** (control plane only, once):

```bash
talosctl --talosconfig talos/talosconfig config endpoint 10.0.0.81
talosctl --talosconfig talos/talosconfig bootstrap -n 10.0.0.81
talosctl --talosconfig talos/talosconfig kubeconfig talos/kubeconfig -n 10.0.0.81
helm upgrade cilium cilium/cilium --install --version 1.20.0 \
  --namespace kube-system -f talos/cilium/cilium-values.yaml
kubectl apply -f talos/cilium/cilium-lb.yaml
```

**Back up every volume** (against k3s). In the Longhorn UI, select all volumes on the Volume page and choose *Create Backup*. Then wait until the Backup page shows a completed backup with today's timestamp for each one.

**Restore volumes** (against Talos, before Flux deploys the apps). On the Longhorn UI's Backup page, restore each volume's latest backup under its original volume name. Use RWX for Nextcloud's data volume. When a restore finishes, open the volume and choose *Create PV/PVC* with *Use Previous PVC*, so the PVC comes back with its original name and namespace. When Flux later creates the StatefulSets and Deployments, they bind to the restored data instead of provisioning empty volumes. Skip volumes that aren't worth restoring, such as Prometheus's 7-day TSDB.

**Switch the ingress VIP.** Change `io.cilium/lb-ipam-ips` in `talos/cilium/cilium-values.yaml` to `10.0.0.240`, and change the range in `talos/cilium/cilium-lb.yaml` to `10.0.0.240`–`10.0.0.250`. Then re-run the `helm upgrade` and `kubectl apply` from *Bootstrap the cluster*.

**Health check:** `talosctl health -n 10.0.0.81`, `flux check`, `flux get kustomizations`, and `kubectl -n longhorn-system get pods`.

## 7. Phases

### Phase 0 — Prepare (no impact)

Write the `talos/` directory and the pilot folder, and merge them **into `main`**. Flux bootstraps from `main`, and `clusters/talos-pilot/` has to be there. Nothing existing is touched, so the k3s cluster is unaffected: its Flux only reads `./clusters/staging`. Validate offline with `talosctl gen config` (§5), `talosctl validate --mode metal -c talos/controlplane.yaml` and `kubectl kustomize` on the two infrastructure paths.

Confirm in the Longhorn UI that every volume has a recent successful backup. Take independent copies as insurance: `pg_dump` of the linkding and Firefly III databases, a `mariadb-dump` of Nextcloud, and the Uptime Kuma data. Store the age key safely.

### Phase 1 — Drain `.77` and install Talos (no downtime)

1. *Evict* `.77` from k3s (§6), then wait for Longhorn to rebuild replicas on `.75` and `.76`. Check that their disks have room for all replicas before you start.
2. *Install Talos* on it (§6): boot the USB ISO and confirm the install disk and the NIC name in maintenance mode.
3. Generate the configs (§5) and apply `controlplane.yaml`. The applied config moves the node to `10.0.0.81`, and every later `talosctl` call targets `.81`. Then *bootstrap the cluster* (§6). For the pilot, `patches/control-plane.yaml` removes the control-plane taint, because the node is the only one, and Cilium uses the `.230` range.
4. **Bootstrap Flux.** Everything before `flux bootstrap` has to exist first:
   - `kubectl apply -f talos/cilium/cilium-lb.yaml` (part of the bootstrap in §6), so the ingress Service gets `10.0.0.230`.
   - The `sops-age` Secret. `infrastructure-controllers` can't build without it, because the cert-manager, Tailscale and Renovate Secrets are SOPS-encrypted:
     ```bash
     kubectl create namespace flux-system
     kubectl -n flux-system create secret generic sops-age --from-file=age.agekey=./age.agekey
     ```
   - The branch is merged into `main` (Phase 0).

   Then bootstrap Flux to the pilot path:
   ```bash
   flux check --pre
   flux bootstrap github --owner=$GITHUB_USER --repository=k8s-cluster \
     --branch=main --path=./clusters/talos-pilot --personal
   ```
   This commits `clusters/talos-pilot/flux-system/` and adds a second deploy key next to the k3s one. Flux deploys cert-manager, Kyverno, Longhorn, goldpinger, reflector and the Cilium configs from your existing manifests. `infrastructure-configs` errors for a minute or two until the cert-manager CRDs exist, because it has no `dependsOn`. It succeeds on retry. Longhorn shows volumes as degraded on one node (`numberOfReplicas: "2"`), which is expected.
5. **Longhorn S3 Secret.** Once Flux has created `longhorn-system`, run `terraform -chdir=terraform apply -var kubeconfig_path=../talos/kubeconfig`. The plan must show only a *create* of `kubernetes_secret.longhorn_backup_credentials` and nothing in the IAM module. Both clusters share one state key, so from then on Terraform tracks the Talos copy. The k3s Secret stays in place but is no longer managed.
6. **Add worker-1 (`.76`).** This leaves k3s with one schedulable worker (`.75`), because `.78` is the tainted control plane, so do it deliberately:
   - Check that `.75` can hold all of k3s's workloads (`kubectl top nodes` on k3s: it takes over `.76`'s load on 16 GB).
   - *Back up every volume* (§6) on k3s first. After this step each k3s volume has only one replica left, on `.75`.
   - Don't use the Longhorn eviction from *Evict a k3s node*. With `numberOfReplicas: "2"` and only one storage node left, the replicas have nowhere to go and the eviction never finishes. Set only `allowScheduling: false` on `.76`'s `nodes.longhorn.io` object, then `kubectl drain` and `kubectl delete node`. Longhorn marks the volumes *Degraded* and keeps serving them from `.75`.
   - *Install Talos* (§6) on `.76` with `worker.yaml`. The node comes up as `worker-1` on `10.0.0.82`. On the Talos cluster Longhorn now has two nodes, so new volumes there are healthy instead of degraded.

### Phase 2 — Restore rehearsal (no downtime)

Restore linkding's two volumes on the new cluster and check the data through a port-forward. One way to run linkding there without its cloudflared is a temporary extra Kustomization in the pilot folder pointing at `./apps/base/linkding`. Also time the restore of one larger volume, so you can size the cutover window, since Nextcloud's 40 GiB dominates it. This phase shakes out the restore procedure and any Talos surprises. Afterwards, delete the rehearsal workloads and volumes from the new cluster. The old cluster stays live throughout.

### Phase 3 — Cutover (planned window, roughly 1–3 hours of downtime)

1. **Freeze the old cluster.** Turn on Nextcloud maintenance mode. Run `flux suspend kustomization --all` on k3s, then scale the apps and cloudflared to zero. *Back up every volume* (§6) on k3s and wait for it to finish, then suspend the RecurringJob. Scale the Tailscale operator to zero and delete the old `k8s-home-subnet-router` device in the Tailscale console.
2. **Wipe the rest.** Copy `/var/lib/rancher/k3s/server/db` and `token` from `.78` to your laptop. This is the point of no return. Then *install Talos* (§6) on `.78` and `.75` with `worker.yaml` and a per-node patch for each (§5). `.76` is already `worker-1`. Because the old Cilium is gone with them, `.240` is now free.
3. **Return `.81` to a dedicated control plane.** Remove the `KubeNodeConfig` taint-removal document from `patches/control-plane.yaml`, then regenerate and re-apply. Drain and uncordon `.81` so pilot workloads move to the workers, and disable Longhorn scheduling on it, so storage lives on the three workers exactly as today.
4. **Switch the VIP** (§6), which moves the pool to `.240–.250`.
5. **Restore data** (§6).
6. **Hand over to the normal staging path.** Re-run the `flux bootstrap` command from Phase 1 with `--path=./clusters/staging`. Flux re-points to the same path as today and adopts the infrastructure Kustomizations. Tailscale, Renovate and the RecurringJob appear, and monitoring and apps deploy onto the restored PVCs. cloudflared reconnects the tunnel, and the Connector re-advertises `10.0.0.240/28`.
7. **Verify** the public and VPN-only endpoints, then turn off Nextcloud maintenance mode. Trigger one manual Longhorn backup and check that it lands in S3.

Until step 2, rolling back means resuming Flux on k3s and scaling the apps back up. After step 2, recovery relies on S3 plus the Phase 0 dumps, both of which Phase 2 has already proven.

### Phase 4 — Clean up (no impact)

Delete `clusters/talos-pilot/`. Optionally remove the k3s playbooks (`prepare_k3s`, `configure_image_gc`, `install_cilium`, `uninstall_k3s`) and update the README's OS column and install instructions. Two small follow-ups:

- The `chaos` skill expects the `k3s-ansible` kube context and uses SSH for host-level faults. You can rename the Talos context to `k3s-ansible` in your kubeconfig to keep it working, but the SSH-based faults need `talosctl` equivalents.
- kube-prometheus-stack will scrape Talos's etcd, scheduler and controller-manager once `patches/control-plane.yaml` sets their metrics bind addresses to `0.0.0.0`. That is a Talos config change, not a repo change.

For future Talos upgrades, `talosctl upgrade` per node (control plane first) with the installer image from your schematic is enough at this size. Renovate can bump the Talos version in the installer image in `patches/common.yaml` if you add a regex manager.

## 8. Risks

| Risk | Mitigation |
|---|---|
| A restore from S3 fails or is incomplete | Rehearsed in Phase 2; database dumps from Phase 0; S3 versioning on the bucket |
| Old cluster tight on disk while `.77` is out | Check Longhorn disk headroom on `.75`/`.76` before evicting |
| After worker-1 joins, k3s runs on a single worker with one replica per volume | Fresh backup right before; check `.75` memory headroom; keep the window until cutover short |
| Cilium `devices: eno+` doesn't match Talos's NIC name | Checked in maintenance mode before bootstrap |
| Both clusters announce the same IP on the shared switch | Pilot uses `.230–.235`; `.240` moves only after the old nodes are wiped |
| Losing remote access during the window | Do the cutover from the LAN; the Tailscale extension on `.81` restores remote `kubectl`/`talosctl` independently of the in-cluster subnet router |
