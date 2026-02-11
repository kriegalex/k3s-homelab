# qBittorrent NFS Storage

NFS PersistentVolume for qBittorrent download storage (torrent downloads).

## Overview

This NFS share provides persistent storage for qBittorrent's downloads directory, allowing downloaded torrents to be accessible by media automation tools (Radarr, Sonarr, Lidarr).

## Apply

```fish
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/media-automation/qbittorrent/nfs/nfs-torrent.yaml
```

## Storage Details

- **PV Name**: `nfs-torrent`
- **PVC Name**: `nfs-torrent`
- **Namespace**: `default`
- **NFS Server**: `10.0.0.2`
- **NFS Path**: `/mnt/user/torrent`
- **NFS Version**: `4.2`
- **Access Mode**: `ReadWriteMany`
- **Storage Size**: `1Mi` (symbolic - NFS doesn't enforce quotas)

## Verification

Check PV/PVC binding:

```fish
kubectl get pv nfs-torrent
kubectl get pvc nfs-torrent
```

Expected output:
```
NAME          STATUS   VOLUME        CAPACITY   ACCESS MODES
nfs-torrent   Bound    nfs-torrent   1Mi        RWX
```

## Troubleshooting

For NFS connectivity issues, mount errors, or PVC stuck in Pending state, see:
- [General NFS Storage Guide](../../../storage/nfs-shares/README.md)
- [Shared Media NFS Guide](../../../storage/nfs-shares/shared-media/README.md)
