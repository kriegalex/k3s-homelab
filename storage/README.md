# Storage Infrastructure

This directory contains all storage layer components for the Kubernetes cluster.

## Storage Backends

### Longhorn - Distributed Block Storage
Location: `storage/longhorn/`
- **Access Mode**: ReadWriteOnce (RWO) - Single pod access
- **Replication**: 2-3 replicas across nodes (HA)
- **Use Cases**: Database volumes, application state, config files
- **Storage Classes**: `longhorn`, `longhorn-single-replica`, `fast-nvme`

### NFS - Shared Network Storage
Location: `storage/nfs-shares/`
- **Access Mode**: ReadWriteMany (RWX) - Multi-pod access
- **Provisioning**: Static PVs + dynamic via nfs-client StorageClass
- **Use Cases**: Media libraries, shared datasets, bulk storage
- **NFS Server**: 10.0.0.2 (external)
- **Organization**: Shared media in `nfs-shares/shared-media/`, app-specific in each app's `nfs/` directory

## When to Use Which Storage Backend

| Use Case | Storage Backend | Reason |
|----------|----------------|--------|
| PostgreSQL database | Longhorn | Needs HA replication, RWO |
| Redis cache | Longhorn | Needs persistence, RWO |
| Plex media library | NFS | Needs RWX for transcoding |
| Plex config | Longhorn | Needs HA, RWO |
| Immich photos | NFS | Large datasets, shared access |
| Immich database | Longhorn (via CNPG) | Needs HA, RWO |

## Deployment Order

1. **Longhorn** - Required for database volumes
2. **NFS Provisioner** - Required for shared media access
3. **CloudNativePG** - Requires Longhorn for storage

See individual directories for detailed installation guides.
