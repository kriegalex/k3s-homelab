# Storage Configuration

This cluster supports multiple storage approaches to meet different application requirements. This guide explains when to use each option and how to configure them.

## Overview

The cluster provides three storage solutions:

1. **Static NFS Shares** - Primary pattern for shared media and large datasets
2. **Longhorn Distributed Storage** - For high-availability replicated storage
3. **NFS Dynamic Provisioning** - Optional automated provisioning via NFS Subdir External Provisioner

Configuration files:
- Static NFS PV/PVC definitions: `nfs-storage/*.yaml`
- Longhorn configuration: `storage/longhorn/custom-values.yaml`
- NFS Provisioner config: `nfs-storage/helm-values-nfs-subdir-external-provisioner.yaml`

## Storage Options Comparison

| Feature | Static NFS | Longhorn | NFS Provisioner |
|---------|-----------|----------|-----------------|
| **Use Case** | Shared media, large datasets | HA databases, replicated storage | Dynamic provisioning |
| **Access Mode** | ReadWriteMany | ReadWriteOnce/ReadWriteMany | ReadWriteMany |
| **Primary Use** | ✅ Yes | For critical services | Optional |
| **Setup Complexity** | Low (manual PV/PVC) | Medium (operator install) | Low (helm chart) |
| **Typical Size** | Large (TBs) | Small-Medium (GBs) | Variable |
| **Examples** | Movies, TV, Nextcloud data | Plex config, HA databases | Temporary storage |

---

## Option 1: Static NFS Shares (Primary Pattern)

Static NFS shares are the primary storage pattern for this cluster. They mount existing NFS exports from the home NFS server (10.0.0.2) as Kubernetes persistent volumes.

### When to Use

- Media libraries (movies, TV shows, anime)
- Shared application data (Nextcloud, Gitea, Immich)
- Large datasets requiring ReadWriteMany access
- Content that exists on the NFS server

### How It Works

Each static NFS share requires:
1. A **PersistentVolume (PV)** defining the NFS mount
2. A **PersistentVolumeClaim (PVC)** binding to that PV

**Example** (`nfs-movies.yaml`):

```yaml
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-movies
spec:
  storageClassName: ""  # Empty string for static binding
  capacity:
    storage: 1Mi  # Nominal size (NFS doesn't enforce limits)
  accessModes:
    - ReadWriteMany
  nfs:
    server: 10.0.0.2
    path: "/mnt/user/movies"
  mountOptions:
    - nfsvers=4.2
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-movies
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 1Mi
  volumeName: nfs-movies  # Binds to specific PV
```

### Available NFS Shares

The following static NFS PV/PVC pairs are available in this directory:

#### Media Libraries
- `nfs-anime` → `/mnt/user/anime`
- `nfs-tv` → `/mnt/user/tv`
- `nfs-movies` → `/mnt/user/movies`

#### Torrent
- `nfs-torrent` → `/mnt/user/torrent`

#### Content Applications
- `nfs-nextcloud` → `/mnt/user/nextcloud`
- `nfs-immich` → `/mnt/user/immich`
- `nfs-gitea` → `/mnt/user/gitea`
- `nfs-paperless` → `/mnt/user/paperless`

#### Backup
- `nfs-backup` → `/mnt/user/backup`

### Deployment Instructions

**Prerequisites:**
Install NFS client tools on all worker nodes:

```bash
sudo apt-get install -y nfs-common
```

**Apply PV/PVC manifests by category:**

**Media:**
```bash
kubectl apply -f nfs-anime-pv.yaml
kubectl apply -f nfs-anime-pvc.yaml

kubectl apply -f nfs-tv-pv.yaml
kubectl apply -f nfs-tv-pvc.yaml

kubectl apply -f nfs-movies-pv.yaml
kubectl apply -f nfs-movies-pvc.yaml
```

**Torrent:**
```bash
kubectl apply -f nfs-torrent-pv.yaml
kubectl apply -f nfs-torrent-pvc.yaml
```

**Nextcloud:**
```bash
kubectl apply -f nfs-nextcloud-pv.yaml
kubectl apply -f nfs-nextcloud-pvc.yaml
```

**Immich:**
```bash
kubectl apply -f nfs-immich-pv.yaml
kubectl -n immich apply -f nfs-immich-pvc.yaml
```

**Gitea:**
```bash
kubectl apply -f nfs-gitea-pv.yaml
kubectl apply -f nfs-gitea-pvc.yaml
```

**Paperless:**
```bash
kubectl apply -f nfs-paperless-pv.yaml
kubectl apply -f nfs-paperless-pvc.yaml
```

**Backup:**
```bash
kubectl apply -f nfs-backup-pv.yaml
kubectl apply -f nfs-backup-pvc.yaml
```

### Using in Applications

Reference the PVC in your Helm values or pod specs:

```yaml
persistence:
  media:
    enabled: true
    existingClaim: nfs-movies  # Use pre-created PVC
```

---

## Option 2: Longhorn Distributed Storage

Longhorn provides distributed block storage with replication and high availability. It's deployed as the default storage class in this cluster.

### When to Use

- Critical application configs requiring HA (e.g., Plex config)
- Databases needing replication
- Services where data loss is unacceptable
- ReadWriteOnce workloads needing failover

### Features

- **2-replica high availability** (configured in custom-values.yaml)
- **Snapshot and backup support**
- **Web UI for management** (can be exposed via ingress)
- **Automatic volume replication** across nodes

### Configuration

**Storage Class:** `longhorn` (default storage class)
**Config Location:** `storage/longhorn/custom-values.yaml`

Key settings:
- `defaultReplicaCount: 2` - Each volume is replicated twice
- `reclaimPolicy: Delete` - Volumes deleted when PVC is deleted
- `defaultFsType: ext4` - Filesystem type

### Example Usage

In Helm values or PVC manifests:

```yaml
persistence:
  config:
    enabled: true
    storageClass: longhorn  # Uses Longhorn distributed storage
    size: 200Gi
```

Or in a standalone PVC:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-app-config
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 50Gi
```

### Real-World Example

Plex uses Longhorn for config storage:

```yaml
persistence:
  config:
    enabled: true
    storageClass: longhorn
    accessMode: ReadWriteOnce
    size: 200Gi
```

This ensures Plex configuration survives node failures.

---

## Option 3: NFS Dynamic Provisioning (Optional)

The NFS Subdir External Provisioner is available for automatic PVC provisioning. This is **not the primary pattern** but can be useful for specific scenarios.

### When to Use

- Applications needing automatic storage creation
- Temporary or ephemeral storage
- When you prefer automation over manual PV creation
- Prototyping or testing

### How It Works

The provisioner automatically creates subdirectories on the NFS server when you create a PVC with the `nfs-client` storage class.

**Storage Class:** `nfs-client`
**Config Location:** `helm-values-nfs-subdir-external-provisioner.yaml`
**Auto-created path:** `/mnt/user/k8s-data/<namespace>-<pvc-name>-<pv-name>`

### Simple Example

Create a PVC without defining a PV:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-app-data
  namespace: default
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: nfs-client
  resources:
    requests:
      storage: 10Gi
```

The provisioner will automatically:
1. Create a directory: `/mnt/user/k8s-data/default-my-app-data-pvc-xxxxx`
2. Create and bind a PV
3. Mount it to your pod

### In Helm Values

```yaml
persistence:
  data:
    enabled: true
    storageClass: nfs-client  # Use dynamic NFS provisioning
    size: 10Gi
```

**Note:** This is less common in this cluster. Most applications use static NFS shares or Longhorn.

---

## NFS Server Configuration

- **Server IP:** 10.0.0.2
- **NFS Version:** 4.2
- **Base Path:** `/mnt/user/`
- **Protocol:** TCP
- **Available Shares:** See "Available NFS Shares" under Option 1

### Prerequisites

All Kubernetes worker nodes must have NFS client utilities installed:

```bash
sudo apt-get update
sudo apt-get install -y nfs-common
```

### Verifying NFS Connectivity

Test NFS mount from a worker node:

```bash
# Create test mount point
sudo mkdir -p /mnt/test

# Test mount
sudo mount -t nfs -o nfsvers=4.2 10.0.0.2:/mnt/user/movies /mnt/test

# Verify
ls /mnt/test

# Unmount
sudo umount /mnt/test
```

---

## Quick Start Examples

### Deploying a Media Application (Radarr)

Uses static NFS for media, Longhorn or hostPath for config:

```bash
# Apply media library PVCs
kubectl apply -f nfs-movies-pv.yaml
kubectl apply -f nfs-movies-pvc.yaml

# Install with Helm
helm install radarr k8s-at-home/radarr -f radarr/custom-values.yaml
```

Helm values reference the NFS PVC:

```yaml
persistence:
  config:
    enabled: true
    storageClass: longhorn  # Config on Longhorn
    size: 10Gi

  media:
    enabled: true
    existingClaim: nfs-movies  # Media on static NFS
```

### Deploying a Content Application (Nextcloud)

Uses static NFS for data:

```bash
# Apply Nextcloud NFS PVC
kubectl apply -f nfs-nextcloud-pv.yaml
kubectl apply -f nfs-nextcloud-pvc.yaml

# Install with Helm
helm install nextcloud nextcloud/nextcloud -f nextcloud/custom-values.yaml
```

### High-Availability Database

Uses Longhorn for replication:

```yaml
persistence:
  enabled: true
  storageClass: longhorn
  size: 20Gi
```

---

## Troubleshooting

### Check PV/PVC Status

```bash
kubectl get pv
kubectl get pvc -A
kubectl describe pvc <pvc-name>
```

### NFS Mount Issues

Check NFS server connectivity:

```bash
showmount -e 10.0.0.2
```

Check pod events:

```bash
kubectl describe pod <pod-name>
```

### Longhorn Issues

Access Longhorn UI (if ingress enabled) or check volume status:

```bash
kubectl get volumes -n longhorn-system
kubectl describe volume <volume-name> -n longhorn-system
```

---

## Summary

**Use Static NFS when:**
- Sharing large media libraries
- Mounting existing NFS data
- Need ReadWriteMany access

**Use Longhorn when:**
- Need high availability
- Replicated storage is critical
- Databases or important configs

**Use NFS Provisioner when:**
- Want dynamic provisioning
- Prototyping or testing
- Temporary storage needs

For most applications in this cluster: **Static NFS for data, Longhorn for critical configs.**
