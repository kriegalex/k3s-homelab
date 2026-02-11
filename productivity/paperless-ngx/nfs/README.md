# Paperless-ngx NFS Storage

NFS PersistentVolumes for Paperless-ngx document storage with separate volumes for media, consume, and export directories.

## Overview

Paperless-ngx uses three NFS shares for different purposes:
1. **nfs-paperless-media**: Stored document files and thumbnails
2. **nfs-paperless-consume**: Inbox directory for new documents to be processed
3. **nfs-paperless-export**: Directory for document exports

## Apply

```fish
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/productivity/paperless-ngx/nfs/nfs-paperless-media.yaml
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/productivity/paperless-ngx/nfs/nfs-paperless-consume.yaml
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/productivity/paperless-ngx/nfs/nfs-paperless-export.yaml
```

## Storage Details

### Media (Document Storage)
- **PV Name**: `nfs-paperless-media`
- **PVC Name**: `nfs-paperless-media`
- **Namespace**: `paperless`
- **NFS Server**: `10.0.0.2`
- **NFS Path**: `/mnt/user/paperless/media`
- **NFS Version**: `4.2`
- **Access Mode**: `ReadWriteMany`
- **Storage Size**: `100Gi`
- **Purpose**: Stores processed documents, thumbnails, and archives

### Consume (Inbox)
- **PV Name**: `nfs-paperless-consume`
- **PVC Name**: `nfs-paperless-consume`
- **Namespace**: `paperless`
- **NFS Server**: `10.0.0.2`
- **NFS Path**: `/mnt/user/paperless/consume`
- **NFS Version**: `4.2`
- **Access Mode**: `ReadWriteMany`
- **Storage Size**: `10Gi`
- **Purpose**: Inbox for new documents to be imported and processed

### Export
- **PV Name**: `nfs-paperless-export`
- **PVC Name**: `nfs-paperless-export`
- **Namespace**: `paperless`
- **NFS Server**: `10.0.0.2`
- **NFS Path**: `/mnt/user/paperless/export`
- **NFS Version**: `4.2`
- **Access Mode**: `ReadWriteMany`
- **Storage Size**: `10Gi`
- **Purpose**: Directory for exported documents (manual exports or bulk operations)

## Verification

Check PV/PVC binding:

```fish
kubectl get pv | grep nfs-paperless
kubectl get pvc -n paperless | grep nfs-paperless
```

Expected output:
```
NAME                     STATUS   VOLUME                   CAPACITY   ACCESS MODES
nfs-paperless-media      Bound    nfs-paperless-media      100Gi      RWX
nfs-paperless-consume    Bound    nfs-paperless-consume    10Gi       RWX
nfs-paperless-export     Bound    nfs-paperless-export     10Gi       RWX
```

## Usage in Helm Values

Reference these PVCs in your Paperless Helm values:

```yaml
persistence:
  media:
    enabled: true
    existingClaim: nfs-paperless-media

  consume:
    enabled: true
    existingClaim: nfs-paperless-consume

  export:
    enabled: true
    existingClaim: nfs-paperless-export
```

## Troubleshooting

For NFS connectivity issues, mount errors, or PVC stuck in Pending state, see:
- [General NFS Storage Guide](../../../storage/nfs-shares/README.md)
- [Media Automation NFS Guide](../../../media-automation/nfs/README.md)
