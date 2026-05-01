# Kubernetes (k8s) homelab charts

These are the charts that I use in my homelab. Feel free to inspire yourself from them or fork them and modify them.

## Repository Structure

This repository contains Helm-based deployment configurations for both infrastructure and applications on Kubernetes.

### Infrastructure Components

Core cluster infrastructure for ingress, storage, database, backup, and monitoring:

- **Ingress Layer**
  - [traefik](ingress/traefik/) - Traefik v3 Ingress controller (replaced ingress-nginx in April 2026)
  - [cert-manager](ingress/cert-manager/) - X.509 certificate management (Let's Encrypt, Infomaniak, Route53)

- **Storage Layer**
  - [longhorn](storage/longhorn/) - Distributed block storage for Kubernetes
  - [nfs-client](storage/nfs-shares/nfs-client/) - Dynamic NFS provisioner for shared storage

- **Database Layer**
  - [cloudnative-pg](database/cloudnative-pg/) - PostgreSQL operator for HA database clusters

- **Backup Layer**
  - [k8up](backup/k8up/) - Backup operator using Restic for PVCs and databases

- **Monitoring Layer**
  - [prometheus](monitoring/) - Prometheus + Grafana stack (kube-prometheus-stack)

- **Hardware Layer**
  - [intel-gpu-plugin](hardware/intel-gpu-plugin/) - Intel GPU Device Plugin for hardware transcoding

### Applications

Application deployments organized by category:

- **Media Automation Stack:** [media-automation/](media-automation/)
  - [radarr](media-automation/radarr/), [sonarr](media-automation/sonarr/), [lidarr](media-automation/lidarr/)
  - [prowlarr](media-automation/prowlarr/), [seerr](media-automation/seerr/) (Overseerr fork), [clonarr](media-automation/clonarr/) (TRaSH-Guides sync)
  - [qbittorrent](media-automation/qbittorrent/), [flaresolverr](media-automation/flaresolverr/)
- **Game Servers:** [game-servers/](game-servers/)
  - [palworld-server](game-servers/palworld-server/), [satisfactory-server](game-servers/satisfactory-server/)
- **Productivity:** [productivity/](productivity/)
  - [nextcloud](productivity/nextcloud/), [paperless-ngx](productivity/paperless-ngx/)
  - [actual-budget](productivity/actual-budget/), [n8n](productivity/n8n/), [gitea](productivity/gitea/)
- **Media Services:** [plex](plex/), [jellyfin](jellyfin/), [immich](immich/)
- **Cache Layer:** [redis](redis/)
- **Network:** [pihole](pihole/)
- **Utilities:** [bentopdf](bentopdf/)
- **Blockchain:** [bitcoin](blockchain/bitcoin/)
- **Social:** [bluesky-pds](social/bluesky-pds/)

## Installation of the cluster

Please have a look at the main [INSTALL.md](./INSTALL.md).

## Setting up infrastructure

### Recommended Installation Order

1. **Ingress:** [cert-manager](ingress/cert-manager/) → [traefik](ingress/traefik/)
2. **Storage:** [longhorn](storage/longhorn/) and/or [nfs-client](storage/nfs-shares/nfs-client/)
3. **Database:** [cloudnative-pg](database/cloudnative-pg/)
4. **Monitoring:** [prometheus](monitoring/)
5. **Backup:** [k8up](backup/k8up/)

Each infrastructure component has a comprehensive README with:
- Prerequisites and installation steps
- Configuration options
- Usage examples
- Troubleshooting guides
- Migration notes from k3s-ansible (if applicable)

### Quick Start: Traefik

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm upgrade --install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace \
  --version 39.0.8 \
  -f ingress/traefik/values.yaml

kubectl apply -f ingress/traefik/ingressroute-dashboard.yaml
kubectl apply -f ingress/traefik/middlewares/
```

See [Traefik README](ingress/traefik/README.md) for full details.

## Setting up applications

Navigate to the folder you are interested in, a README should be in there. If not, please raise an issue. Thanks.

## Migration from k3s-ansible

This repository contains infrastructure components migrated from the [k3s-ansible](https://github.com/kriegalex/k3s-ansible) repository. The k3s-ansible project handles cluster provisioning and infrastructure automation, while k8s-homelab focuses on manual Helm-based deployments with comprehensive documentation.

For migration details, see [MIGRATION-SUMMARY.md](MIGRATION-SUMMARY.md).

## Contributing

Feel free to open issues or pull requests if you find bugs or have suggestions for improvements.

## License

See [LICENSE](LICENSE) file for details.
