# Kubernetes (k8s) homelab charts

These are the charts that I use in my homelab. Feel free to inspire yourself from them or fork them and modify them.

## Repository Structure

This repository contains Helm-based deployment configurations for both infrastructure and applications on Kubernetes.

### Infrastructure Components (Deployed)

Core cluster infrastructure for ingress, storage, database, backup, and monitoring:

- **Ingress Layer**
  - [traefik](ingress/traefik/) - Traefik v3 Ingress controller (replaced ingress-nginx in April 2026)
  - [cert-manager](ingress/cert-manager/) - X.509 certificate management (Let's Encrypt, Infomaniak, Route53)

- **Storage Layer**
  - [longhorn](storage/longhorn/) - Distributed block storage for Kubernetes

- **Database Layer**
  - [cloudnative-pg](database/cloudnative-pg/) - PostgreSQL operator for HA database clusters

- **Backup Layer** - CNPG barman → QNAP S3 (weekly) + Longhorn → S3 (weekly) + [Exoscale SOS rclone mirror](backup/exoscale-s3/); see [claude-docs/backup-strategy.md](claude-docs/backup-strategy.md) for full posture

- **Monitoring Layer**
  - [prometheus](monitoring/) - Prometheus + Grafana stack (kube-prometheus-stack)
  - [ntfy](monitoring/ntfy/), [alertmanager-ntfy](monitoring/alertmanager-ntfy/) - push notifications for alerts

- **Hardware Layer**
  - [intel-gpu-plugin](hardware/intel-gpu-plugin/) - Intel GPU Device Plugin for hardware transcoding

### Applications (Deployed)

Application deployments organized by category:

- **Media Automation Stack:** [media-automation/](media-automation/)
  - [radarr](media-automation/radarr/), [sonarr](media-automation/sonarr/) (tv + anime instances), [lidarr](media-automation/lidarr/)
  - [prowlarr](media-automation/prowlarr/), [seerr](media-automation/seerr/) (Overseerr fork), [clonarr](media-automation/clonarr/) (TRaSH-Guides sync)
  - [qbittorrent](media-automation/qbittorrent/) (media + anime instances), [flaresolverr](media-automation/flaresolverr/)
- **Game Servers:** [game-servers/](game-servers/)
  - [palworld-server](game-servers/palworld-server/), [satisfactory-server](game-servers/satisfactory-server/)
  - [enshrouded-server](game-servers/enshrouded-server/), [valheim-server](game-servers/valheim-server/)
- **Productivity:** [productivity/](productivity/)
  - [nextcloud](productivity/nextcloud/), [paperless-ngx](productivity/paperless-ngx/)
  - [actual-budget](productivity/actual-budget/), [n8n](productivity/n8n/)
- **Media Services:** [plex](plex/), [jellyfin](jellyfin/), [immich](immich/)
- **Social:** [bluesky-pds](social/bluesky-pds/), [nostr-strfry](social/nostr-strfry/)
- **Blockchain:** [deltabadger](blockchain/deltabadger/)
- **Utilities:** [bentopdf](bentopdf/)

### Available (not currently deployed)

Directories exist in this repo but nothing is running in-cluster for these:

- [k8up](backup/k8up/) - Restic backup operator (superseded by the backup posture above)
- [nostr-rs-relay](social/nostr-rs-relay/) - SQLite nostr relay (decommissioned 2026-07-26, consolidated onto strfry; kept as a template)
- [pihole](pihole/) - DNS ad-blocking
- [redis](redis/) - standalone cache layer
- [gitea](productivity/gitea/) - Git hosting (a separate Gitea runs on a Pi instead)
- [bitcoin](blockchain/bitcoin/) - Bitcoin node

## Installation of the cluster

Please have a look at the main [INSTALL.md](./INSTALL.md).

## Setting up infrastructure

### Recommended Installation Order

1. **Ingress:** [cert-manager](ingress/cert-manager/) → [traefik](ingress/traefik/)
2. **Storage:** [longhorn](storage/longhorn/)
3. **Database:** [cloudnative-pg](database/cloudnative-pg/)
4. **Monitoring:** [prometheus](monitoring/)
5. **Backup:** [Exoscale SOS rclone mirror](backup/exoscale-s3/) (see [claude-docs/backup-strategy.md](claude-docs/backup-strategy.md))

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
