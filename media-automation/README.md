# Media Automation Stack

This directory contains the complete media automation stack for downloading, managing, and requesting media content.

## Applications

- **[radarr](radarr/)** - Movie collection manager for Usenet and BitTorrent
- **[sonarr](sonarr/)** - TV series collection manager (TV shows and anime)
- **[lidarr](lidarr/)** - Music collection manager
- **[prowlarr](prowlarr/)** - Indexer manager for radarr, sonarr, and lidarr
- **[overseerr](overseerr/)** - Request management and media discovery
- **[qbittorrent](qbittorrent/)** - BitTorrent client with VPN support (ProtonVPN/PIA)
- **[flaresolverr](flaresolverr/)** - Proxy server to bypass Cloudflare protection

## Architecture

This stack follows the standard *arr workflow:

1. **Request** → Users request media via Overseerr
2. **Search** → Prowlarr searches configured indexers
3. **Download** → Radarr/Sonarr/Lidarr send torrents to qBittorrent
4. **Process** → Media is organized and renamed automatically
5. **Consume** → Plex/Jellyfin serve the media

## Shared Dependencies

### NFS Storage

All applications share centralized NFS volumes for media storage:

- **Movies**: `nfs-movies` (used by radarr, plex, jellyfin)
- **TV Shows**: `nfs-tv` (used by sonarr, plex, jellyfin)
- **Music**: `nfs-music` (used by lidarr, plex, jellyfin)
- **Anime**: `nfs-anime` (used by sonarr, plex, jellyfin)
- **Torrent Downloads**: `nfs-torrent` (used by qbittorrent, radarr, sonarr, lidarr)

Apply NFS PVCs before deploying applications:

**Media libraries:**
```fish
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/media-automation/nfs/nfs-movies.yaml
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/media-automation/nfs/nfs-tv.yaml
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/media-automation/nfs/nfs-anime.yaml
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/media-automation/nfs/nfs-music.yaml
```

**Torrent downloads:**
```fish
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/media-automation/qbittorrent/nfs/nfs-torrent.yaml
```

See [Media NFS README](nfs/README.md) for details and [NFS storage guide](../storage/nfs-shares/README.md) for troubleshooting.

### Ingress Rules

Overseerr ingress configuration is located at:

```bash
../ingress/rules/media-automation/overseerr/
```

## Installation Order

1. **Prowlarr** (indexer manager) - Must be configured first
2. **qBittorrent** (download client) - Configure VPN settings
3. **Radarr** (movies) - Add Prowlarr indexers and qBittorrent client
4. **Sonarr** (TV shows) - Add Prowlarr indexers and qBittorrent client
5. **Lidarr** (music) - Add Prowlarr indexers and qBittorrent client
6. **Overseerr** (requests) - Connect to Radarr/Sonarr after they're configured
7. **FlareSolverr** (optional) - Only if encountering Cloudflare-protected indexers

## Configuration Tips

### Prowlarr Setup

After installation, configure Prowlarr first:

1. Add indexers (trackers/Usenet providers)
2. Configure applications (radarr, sonarr, lidarr) with API keys
3. Sync indexers to downstream applications

### qBittorrent VPN

qBittorrent supports ProtonVPN and PIA. Edit `custom-values-proton.yaml` or `custom-values-pia.yaml` with your credentials:

```bash
kubectl create secret generic qbittorrent-vpn-secret \
  --from-literal=username='your-username' \
  --from-literal=password='your-password'
```

### Directory Structure

Each *arr application expects this directory structure:

```
/downloads/      # qBittorrent download location
  ├── movies/    # Radarr watches this
  ├── tv/        # Sonarr watches this
  └── music/     # Lidarr watches this

/media/
  ├── movies/    # Radarr organizes completed movies here
  ├── tv/        # Sonarr organizes completed TV shows here
  └── music/     # Lidarr organizes completed music here
```

## Cross-References

- **Media Servers**: [plex](../plex/), [jellyfin](../jellyfin/)
- **NFS Storage**: [storage/nfs-shares](../storage/nfs-shares/)
- **Ingress Rules**: [ingress/rules/media-automation](../ingress/rules/media-automation/)

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -n media
kubectl logs -n media <pod-name>
```

### Verify NFS Mounts

```bash
kubectl get pvc
kubectl describe pvc nfs-movies
```

### Test VPN Connection

```bash
kubectl exec -n media <qbittorrent-pod> -- curl ifconfig.me
```

Should return your VPN provider's IP, not your home IP.

## Documentation

Each application directory contains a dedicated README with:

- Helm installation commands
- Custom values configuration
- Storage requirements
- Application-specific setup

Navigate to individual application folders for detailed instructions.
