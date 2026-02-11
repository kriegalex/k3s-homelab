# Gitea NFS Storage

NFS PersistentVolume for Gitea repository data.

## Overview

This NFS share provides persistent storage for Gitea's Git repositories, ensuring code persists across pod restarts.

## Apply

```fish
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/productivity/gitea/nfs/nfs-gitea.yaml
```

## Storage Details

- **PV Name**: `nfs-gitea`
- **PVC Name**: `nfs-gitea`
- **Namespace**: `default`
- **NFS Server**: `10.0.0.2`
- **NFS Path**: `/mnt/user/gitea`
- **NFS Version**: `4.2`
- **Access Mode**: `ReadWriteMany`
- **Storage Size**: `1Mi` (symbolic - NFS doesn't enforce quotas)

## Verification

Check PV/PVC binding:

```fish
kubectl get pv nfs-gitea
kubectl get pvc nfs-gitea
```

Expected output:
```
NAME        STATUS   VOLUME      CAPACITY   ACCESS MODES
nfs-gitea   Bound    nfs-gitea   1Mi        RWX
```

## Troubleshooting

For NFS connectivity issues, mount errors, or PVC stuck in Pending state, see:
- [General NFS Storage Guide](../../../storage/nfs-shares/README.md)
- [Shared Media NFS Guide](../../../storage/nfs-shares/shared-media/README.md)
