# k8up NFS Storage

NFS PersistentVolume for k8up backup storage.

## Overview

This NFS share provides persistent storage for k8up's backup repository, ensuring backups persist and are accessible across pod restarts.

## Apply

```fish
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/backup/k8up/nfs/nfs-backup.yaml
```

## Storage Details

- **PV Name**: `nfs-backup`
- **PVC Name**: `nfs-backup`
- **Namespace**: `default`
- **NFS Server**: `10.0.0.2`
- **NFS Path**: `/mnt/user/backup`
- **NFS Version**: `4.2`
- **Access Mode**: `ReadWriteMany`
- **Storage Size**: `1Mi` (symbolic - NFS doesn't enforce quotas)

## Verification

Check PV/PVC binding:

```fish
kubectl get pv nfs-backup
kubectl get pvc nfs-backup
```

Expected output:
```
NAME         STATUS   VOLUME       CAPACITY   ACCESS MODES
nfs-backup   Bound    nfs-backup   1Mi        RWX
```

## Troubleshooting

For NFS connectivity issues, mount errors, or PVC stuck in Pending state, see:
- [General NFS Storage Guide](../../../storage/nfs-shares/README.md)
- [Shared Media NFS Guide](../../../storage/nfs-shares/shared-media/README.md)
