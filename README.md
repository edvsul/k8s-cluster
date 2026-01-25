# k8s-cluster
The kubernetes homelab

## Infrastructure Specifications

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

## Available Application Endpoints

**Public Endpoints:**
- **Linkding bookmarking**: https://ld.edvsul.org
- **Audiobookshelf**: https://audiobookshelf.edvsul.org

**VPN-Only Endpoints:**
- **Grafana**: https://grafana.edvsul.org (requires Tailscale VPN)
