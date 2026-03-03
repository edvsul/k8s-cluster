# k8s-cluster
The kubernetes homelab

## Infrastructure Specifications

**Prerequisites:**
- flux-cli https://fluxcd.io/flux/installation/#install-the-flux-cli
- kubectl https://kubernetes.io/docs/tasks/tools/#kubectl
- git https://git-scm.com/downloads
- cloudflared https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/downloads/
- sops https://fluxcd.io/flux/guides/mozilla-sops/

**Hardware:**
- **Systems**: 2x Dell Optiplex 7010
- **CPU**: 2 cores per system
- **RAM**: 8 GB per system
- **OS**: Ubuntu Server 24.04

**Kubernetes Distribution:**
- **k3s** - Lightweight Kubernetes distribution

## Networking

- **Access**: Local network only
- **VPN**: Accessible via Tailscale VPN for remote access

## GitOps

- **GitOps Tool**: FluxCD
- **Purpose**: Automated deployment and configuration management

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

## Available Application Endpoints

**Public Endpoints:**
- **Linkding bookmarking**: https://ld.edvsul.org
- **Audiobookshelf**: https://audiobookshelf.edvsul.org

**VPN-Only Endpoints:**
- **Grafana**: https://grafana.edvsul.org (requires Tailscale VPN)
