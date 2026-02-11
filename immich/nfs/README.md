# Immich NFS Storage

NFS PersistentVolumes for Immich photo and video storage, including read-only access to Nextcloud photos.

## Overview

Immich uses two NFS shares:
1. **nfs-immich**: Read-write storage for Immich's own uploaded photos and videos
2. **nfs-nextcloud-ro**: Read-only access to Nextcloud photos for importing/viewing

## Apply

```fish
# Immich's own storage (read-write)
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/immich/nfs/nfs-immich.yaml

# Nextcloud photos (read-only) - optional, for importing from Nextcloud
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/immich/nfs/nfs-nextcloud-ro.yaml
```

## Storage Details

### Immich Storage (Read-Write)
- **PV Name**: `nfs-immich`
- **PVC Name**: `nfs-immich`
- **Namespace**: `immich`
- **NFS Server**: `10.0.0.2`
- **NFS Path**: `/mnt/user/immich`
- **NFS Version**: `4.2`
- **Access Mode**: `ReadWriteMany`
- **Storage Size**: `1Mi` (symbolic - NFS doesn't enforce quotas)

### Nextcloud Photos (Read-Only)
- **PV Name**: `nfs-nextcloud-ro`
- **PVC Name**: `nfs-nextcloud-ro`
- **Namespace**: `immich`
- **NFS Server**: `10.0.0.2`
- **NFS Path**: `/mnt/user/nextcloud`
- **NFS Version**: `4.2`
- **Access Mode**: `ReadOnlyMany`
- **Mount Options**: `ro` (read-only)
- **Storage Size**: `1Mi` (symbolic - NFS doesn't enforce quotas)
- **Purpose**: Import or view photos already stored in Nextcloud

## Verification

Check PV/PVC binding:

```fish
kubectl get pv nfs-immich
kubectl get pvc -n immich nfs-immich

# If using Nextcloud read-only mount
kubectl get pv nfs-nextcloud-ro
kubectl get pvc -n immich nfs-nextcloud-ro
```

Expected output:
```
NAME               STATUS   VOLUME             CAPACITY   ACCESS MODES
nfs-immich         Bound    nfs-immich         1Mi        RWX
nfs-nextcloud-ro   Bound    nfs-nextcloud-ro   1Mi        ROX
```

## Troubleshooting

For NFS connectivity issues, mount errors, or PVC stuck in Pending state, see:
- [General NFS Storage Guide](../../storage/nfs-shares/README.md)
- [Shared Media NFS Guide](../../storage/nfs-shares/shared-media/README.md)
