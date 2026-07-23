# k8s-cluster
The kubernetes homelab

## Infrastructure Specifications

**Prerequisites:**
- flux-cli https://fluxcd.io/flux/installation/#install-the-flux-cli
- kubectl https://kubernetes.io/docs/tasks/tools/#kubectl
- git https://git-scm.com/downloads
- cloudflared https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/downloads/
- sops https://fluxcd.io/flux/guides/mozilla-sops/

**Hardware:** 4 nodes — 1 control plane + 3 workers

| Role | IP | Model | CPU | RAM | OS |
|------|-----|-------|-----|-----|-----|
| Control plane | 10.0.0.78 | Dell OptiPlex 9020 | i3-4150, 4 cores | 8 GB | Ubuntu Server 24.04 LTS |
| Worker | 10.0.0.77 | Dell OptiPlex 7010 | i3-3240, 4 cores | 8 GB | Ubuntu Server 24.04 LTS |
| Worker | 10.0.0.76 | HP EliteDesk 800 G1 TWR | i5-4570, 4 cores | 16 GB | Ubuntu Server 26.04 LTS |
| Worker | 10.0.0.75 | HP EliteDesk 800 G1 TWR | i5-4570, 4 cores | 16 GB | Ubuntu Server 26.04 LTS |

**Kubernetes Distribution:**
- **k3s** - Lightweight Kubernetes distribution

## Networking

- **Access**: Local network only
- **VPN**: Accessible via Tailscale VPN for remote access

## GitOps

- **GitOps Tool**: FluxCD
- **Purpose**: Automated deployment and configuration management

### Prerequisites

1. **Install k3s with k3s-ansible**
2. **Install cilium**

   ```bash
   ansible-playbook ansible/playbooks/install_cilium.yaml -i ansible/inventory/inventory.yaml
   ```


### Bootstrap FluxCD

1. **Set GitHub credentials**:
   ```bash
   export GITHUB_TOKEN=<your-token>
   export GITHUB_USER=<your-username>
   ```

2. **Install Flux CLI**:
   ```bash
   brew install fluxcd/tap/flux
   ```

3. **Verify prerequisites**:
   ```bash
   flux check --pre
   ```

4. **Bootstrap Flux to the cluster**:
   ```bash
   flux bootstrap github \
     --owner=$GITHUB_USER \
     --repository=k8s-cluster \
     --branch=main \
     --path=./clusters/staging \
     --personal
   ```

5. **Create the SOPS age secret** in the `flux-system` namespace for decrypting encrypted secrets.

## Available Application Endpoints

**Public Endpoints:**
- **Linkding bookmarking**: https://ld.edvsul.org
- **Nextcloud**: https://nextcloud.edvsul.org

**VPN-Only Endpoints:**
- **Grafana**: https://grafana.edvsul.org (requires Tailscale VPN)
- **Longhorn**: https://longhorn.edvsul.org (requires Tailscale VPN)
- **Hubble UI**: https://hubble.edvsul.org (requires Tailscale VPN)

## How Traffic Reaches Applications

Applications are exposed through **two independent ingress paths**, depending on
whether they should be reachable from the public internet or only from the home
network / VPN.

### Publicly exposed apps (Nextcloud, Linkding) — Cloudflare Tunnel

These apps are reachable from anywhere with no inbound ports opened on the home
network. A `cloudflared` Deployment runs inside the cluster and dials **outbound**
to Cloudflare's edge, holding a persistent tunnel open.

```
Browser → Cloudflare edge (public DNS + TLS termination)
        → [outbound tunnel] → cloudflared pod
        → http://<app>:<port> (ClusterIP Service) → app pod
```

1. `ld.edvsul.org` / `nextcloud.edvsul.org` are CNAMEs in Cloudflare DNS pointing
   at the tunnel; they resolve to Cloudflare's edge.
2. Cloudflare terminates public TLS and pushes the request **down the existing
   outbound tunnel** — so no firewall rule, public IP, or LoadBalancer is needed.
3. `cloudflared` matches the hostname to an internal ClusterIP Service
   (e.g. `http://linkding:9090`) and proxies the request to the app pod.

### Internally exposed apps (Longhorn, Hubble, Grafana, ...) — Cilium ingress

These apps share a single Cilium ingress LoadBalancer at **`10.0.0.240`** and are
reachable only on the home LAN, or remotely over Tailscale.

```
Client → 10.0.0.240 (Cilium LoadBalancer VIP, L2-announced by one node)
       → Cilium eBPF LoadBalancer → local Envoy proxy (shared ingress)
       → TLS termination (*.edvsul.org) → route by Host header
       → backend ClusterIP Service → app pod
```

1. `*.edvsul.org` (hubble/grafana/longhorn) resolve to **`10.0.0.240`**, a Cilium
   `LoadBalancer` IP allocated from the `lan-pool` (`10.0.0.240–250`).
2. `10.0.0.240` is not bound to any NIC — Cilium **L2-announces** it (policy
   `lan-l2`): one node holds a lease and answers ARP for it on the LAN NIC (`eno1`).
3. Cilium's eBPF datapath redirects the connection to the node-local **Envoy**
   proxy. In `shared` mode a single Envoy/ingress config serves all three hosts.
4. Envoy terminates TLS with the `*.edvsul.org` wildcard certificate
   (issued by cert-manager, synced into the `cilium-secrets` namespace) and routes
   by `Host` header to the matching backend ClusterIP Service.

**Remote access (Tailscale):** `10.0.0.240` is a LAN-only address, so it is not
reachable over the VPN by default. An in-cluster Tailscale **operator + Connector**
runs a subnet router that advertises `10.0.0.240/28` into the tailnet. A remote
client with `--accept-routes` tunnels traffic for that range to the subnet-router
pod, which forwards it into the cluster (the rest of the chain above is identical).

```
Laptop (Tailscale, --accept-routes) → [WireGuard] → subnet-router pod
       → 10.0.0.240 → Cilium LoadBalancer → Envoy → app
```

> Note: `kubectl`/API access is served by a **separate** host-level `tailscaled`
> on the master node (a native tailnet address), independent of the in-cluster
> subnet router used for the ingress apps.
