# Shared Media Libraries

This directory contains NFS PersistentVolume and PersistentVolumeClaim definitions for shared media libraries used across multiple applications (Radarr, Sonarr, Lidarr, Plex, Jellyfin).

## Directory Structure

```
media-automation/nfs/
├── README.md
├── nfs-movies.yaml      # Movies library (default namespace)
├── nfs-tv.yaml          # TV shows library (default namespace)
├── nfs-anime.yaml       # Anime library (default namespace)
└── nfs-music.yaml       # Music library (default namespace)

plex/nfs/
├── README.md
├── nfs-movies-plex.yaml  # Movies library (plex namespace)
├── nfs-tv-plex.yaml      # TV shows library (plex namespace)
├── nfs-anime-plex.yaml   # Anime library (plex namespace)
└── nfs-music-plex.yaml   # Music library (plex namespace)
```

## Architecture

### Base Libraries vs Plex Variants

**Base libraries** (`nfs-movies.yaml`, etc.) are used by:
- Radarr (movies)
- Sonarr (TV shows)
- Lidarr (music)
- Jellyfin (all media)
- Any app running in the `media` namespace

**Plex variants** (`plex/nfs-*-plex.yaml`) are identical PVs pointing to the same NFS paths but with PVCs in the `plex` namespace. This is necessary because Kubernetes PVCs cannot be shared across namespaces.

### Storage Details

- **Namespace**: `media`
- **NFS Server**: `10.0.0.2`
- **NFS Version**: 4.2
- **Access Mode**: ReadWriteMany (multiple pods can mount simultaneously)
- **Storage Size**: 1Mi (symbolic - NFS doesn't enforce quotas)

### NFS Paths

| Library | NFS Path | Base PV/PVC | Plex PV/PVC |
|---------|----------|-------------|-------------|
| Movies | `/mnt/user/movies` | `nfs-movies` | `nfs-movies-plex` |
| TV Shows | `/mnt/user/tv` | `nfs-tv` | `nfs-tv-plex` |
| Anime | `/mnt/user/anime` | `nfs-anime` | `nfs-anime-plex` |
| Music | `/mnt/user/music` | `nfs-music` | `nfs-music-plex` |

## Usage

### Applying Base Libraries

For applications in the `media` namespace (Radarr, Sonarr, Lidarr, Jellyfin):

```fish
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/media-automation/nfs/nfs-movies.yaml
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/media-automation/nfs/nfs-tv.yaml
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/media-automation/nfs/nfs-anime.yaml
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/media-automation/nfs/nfs-music.yaml
```

### Applying Plex Variants

For Plex (namespace: `plex`):

```fish
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/plex/nfs/nfs-movies-plex.yaml
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/plex/nfs/nfs-tv-plex.yaml
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/plex/nfs/nfs-anime-plex.yaml
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/plex/nfs/nfs-music-plex.yaml
```

## Verification

Check PV/PVC binding status:

```fish
# Base libraries (media namespace)
kubectl get pv | grep nfs-movies
kubectl get pvc -n media | grep nfs-movies

# Plex variants (plex namespace)
kubectl get pv | grep nfs-movies-plex
kubectl get pvc -n plex | grep nfs-movies-plex
```

## Troubleshooting

### PVC Stuck in Pending

If a PVC remains in `Pending` state:

1. **Check PV availability**:
   ```fish
   kubectl get pv nfs-movies
   ```
   Status should be `Available` or `Bound`.

2. **Check NFS server connectivity**:
   ```fish
   ping 10.0.0.2
   ```

3. **Test NFS mount manually**:
   ```fish
   # You need to run this with sudo (present to user):
   # sudo mount -t nfs -o nfsvers=4.2 10.0.0.2:/mnt/user/movies /mnt/test
   ```

4. **Check events**:
   ```fish
   kubectl describe pvc nfs-movies
   ```

### Mount Errors in Pods

If pods fail to mount NFS volumes:

1. **Check pod events**:
   ```fish
   kubectl describe pod <pod-name>
   ```

2. **Verify NFS client packages** (on worker nodes - requires sudo):
   ```
   sudo apt list --installed | grep nfs-common
   ```

3. **Check firewall rules** (NFS requires ports 2049, 111):
   ```fish
   # On NFS server - requires sudo to run:
   # sudo ufw status
   ```

## See Also

- [General NFS Storage Guide](../../storage/nfs-shares/README.md) - NFS provisioner setup and troubleshooting
- [Plex NFS Setup](../../plex/nfs/README.md) - Plex namespace-specific PVCs
- [Media Automation](../README.md) - Radarr, Sonarr, Lidarr setup
