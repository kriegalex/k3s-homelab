# Kubernetes (k8s) homelab charts

These are the charts that I use in my homelab. Feel free to inspire yourself from them or fork them and modify them.

## Repository Structure

This repository contains Helm-based deployment configurations for both infrastructure and applications on Kubernetes.

### Infrastructure Components

Core cluster infrastructure for ingress, storage, database, backup, and monitoring:

- **Ingress Layer**
  - [ingress-nginx](ingress/ingress-nginx/) - Kubernetes Ingress controller using NGINX
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
  - [prowlarr](media-automation/prowlarr/), [overseerr](media-automation/overseerr/)
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

1. **Ingress:** [ingress-nginx](ingress/ingress-nginx/) → [cert-manager](ingress/cert-manager/)
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

### Quick Start: ingress-nginx

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --version 4.12.0 \
  -f ingress/ingress-nginx/custom-values.yaml
```

See [ingress-nginx README](ingress/ingress-nginx/README.md) for full details.

## Setting up applications

Navigate to the folder you are interested in, a README should be in there. If not, please raise an issue. Thanks.

## Migration from k3s-ansible

This repository contains infrastructure components migrated from the [k3s-ansible](https://github.com/kriegalex/k3s-ansible) repository. The k3s-ansible project handles cluster provisioning and infrastructure automation, while k8s-homelab focuses on manual Helm-based deployments with comprehensive documentation.

For migration details, see [MIGRATION-SUMMARY.md](MIGRATION-SUMMARY.md).

## Contributing

Feel free to open issues or pull requests if you find bugs or have suggestions for improvements.

## License

See [LICENSE](LICENSE) file for details.
