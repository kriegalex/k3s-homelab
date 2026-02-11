# Plex Media Libraries (Namespace-Specific)

This directory contains NFS PersistentVolume and PersistentVolumeClaim definitions for Plex media libraries in the `plex` namespace.

## Why Namespace-Specific PVCs?

Kubernetes PersistentVolumeClaims cannot be shared across namespaces. Since Plex runs in the `plex` namespace (not `default`), it needs its own PVCs that reference the same NFS paths as the base media libraries.

**Same NFS paths, different namespace:**
- Base apps (Radarr, Sonarr, Lidarr) use PVCs in `default` namespace → [media-automation/nfs/](../../media-automation/nfs/)
- Plex uses PVCs in `plex` namespace → **this directory**
- Both mount the same underlying NFS shares (e.g., `/mnt/user/movies`)

## Available Libraries

| PVC Name | NFS Path | Used For |
|----------|----------|----------|
| `nfs-movies-plex` | `/mnt/user/movies` | Movies |
| `nfs-tv-plex` | `/mnt/user/tv` | TV Shows |
| `nfs-anime-plex` | `/mnt/user/anime` | Anime |
| `nfs-music-plex` | `/mnt/user/music` | Music |

## Apply

Before deploying Plex, apply the necessary media library PVCs:

```fish
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/plex/nfs/nfs-movies-plex.yaml
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/plex/nfs/nfs-tv-plex.yaml
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/plex/nfs/nfs-anime-plex.yaml
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/plex/nfs/nfs-music-plex.yaml
```

## Storage Details

- **NFS Server**: `10.0.0.2`
- **NFS Version**: `4.2`
- **Access Mode**: `ReadWriteMany` (multiple pods can mount simultaneously)
- **Namespace**: `plex`
- **Storage Size**: `1Mi` (symbolic - NFS doesn't enforce quotas)

## Verification

Check PV/PVC binding status:

```fish
# Check PersistentVolumes
kubectl get pv | grep nfs-movies-plex
kubectl get pv | grep nfs-tv-plex
kubectl get pv | grep nfs-anime-plex
kubectl get pv | grep nfs-music-plex

# Check PersistentVolumeClaims in plex namespace
kubectl get pvc -n plex
```

Expected output:
```
NAMESPACE   NAME              STATUS   VOLUME            CAPACITY   ACCESS MODES
plex        nfs-movies-plex   Bound    nfs-movies-plex   1Mi        RWX
plex        nfs-tv-plex       Bound    nfs-tv-plex       1Mi        RWX
plex        nfs-anime-plex    Bound    nfs-anime-plex    1Mi        RWX
plex        nfs-music-plex    Bound    nfs-music-plex    1Mi        RWX
```

## Configuration in Plex Helm Values

Reference these PVCs in your Plex Helm values:

```yaml
persistence:
  config:
    enabled: true
    storageClass: longhorn
    size: 200Gi

  media:
    movies:
      enabled: true
      existingClaim: nfs-movies-plex

    tv:
      enabled: true
      existingClaim: nfs-tv-plex

    anime:
      enabled: true
      existingClaim: nfs-anime-plex

    music:
      enabled: true
      existingClaim: nfs-music-plex
```

## Troubleshooting

### PVC Stuck in Pending

If a PVC remains in `Pending` state:

1. **Check PV availability**:
   ```fish
   kubectl get pv nfs-movies-plex
   ```
   Status should be `Available` or `Bound`.

2. **Check namespace**:
   ```fish
   kubectl get pvc -n plex
   ```
   Ensure you're checking the `plex` namespace, not `default`.

3. **Check NFS server connectivity**:
   ```fish
   ping 10.0.0.2
   ```

4. **Check events**:
   ```fish
   kubectl describe pvc nfs-movies-plex -n plex
   ```

### Mount Errors in Plex Pods

If Plex pods fail to mount NFS volumes:

1. **Check pod events**:
   ```fish
   kubectl describe pod <plex-pod-name> -n plex
   ```

2. **Verify NFS client packages** (on worker nodes - requires sudo):
   ```
   sudo apt list --installed | grep nfs-common
   ```

3. **Test NFS mount manually** (requires sudo):
   ```
   sudo mount -t nfs -o nfsvers=4.2 10.0.0.2:/mnt/user/movies /mnt/test
   ```

## See Also

- [Plex Setup Guide](../README.md) - Full Plex installation instructions
- [Media Automation NFS](../../media-automation/nfs/README.md) - Base media libraries for *arr apps
- [General NFS Storage Guide](../../storage/nfs-shares/README.md) - NFS troubleshooting
