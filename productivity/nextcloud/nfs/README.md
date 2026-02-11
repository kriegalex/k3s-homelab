# Nextcloud NFS Storage

NFS PersistentVolume for Nextcloud user data storage.

## Overview

This NFS share provides persistent storage for Nextcloud user files, ensuring data persists across pod restarts and can be accessed with ReadWriteMany mode.

## Apply

```fish
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/productivity/nextcloud/nfs/nfs-nextcloud.yaml
```

## Storage Details

- **PV Name**: `nfs-nextcloud`
- **PVC Name**: `nfs-nextcloud`
- **Namespace**: `nextcloud`
- **NFS Server**: `10.0.0.2`
- **NFS Path**: `/mnt/user/nextcloud`
- **NFS Version**: `4.2`
- **Access Mode**: `ReadWriteMany`
- **Storage Size**: `1Mi` (symbolic - NFS doesn't enforce quotas)

## Verification

Check PV/PVC binding:

```fish
kubectl get pv nfs-nextcloud
kubectl get pvc -n nextcloud nfs-nextcloud
```

Expected output:
```
NAME            STATUS   VOLUME          CAPACITY   ACCESS MODES
nfs-nextcloud   Bound    nfs-nextcloud   1Mi        RWX
```

## Troubleshooting

For NFS connectivity issues, mount errors, or PVC stuck in Pending state, see:
- [General NFS Storage Guide](../../../storage/nfs-shares/README.md)
- [Shared Media NFS Guide](../../../storage/nfs-shares/shared-media/README.md)
