# NFS Subdir External Provisioner - Dynamic NFS Storage

## Overview

The NFS Subdir External Provisioner is an automatic provisioner for Kubernetes that uses your existing NFS server to support dynamic provisioning of Kubernetes Persistent Volumes via Persistent Volume Claims. It automatically creates subdirectories on your NFS share for each PVC.

**Key features:**
- Dynamic provisioning of PVs from NFS shares
- Automatic subdirectory creation per PVC
- ReadWriteMany (RWX) support for shared storage
- Volume expansion support
- Archive on delete (preserves data when PVC is deleted)

**Use cases:**
- Shared storage for multiple pods (ReadWriteMany)
- Legacy applications requiring NFS
- Media libraries shared across services
- Backup storage
- Static content for web applications

## Prerequisites

- Kubernetes cluster
- NFS server with exported share
- nfs-common installed on all nodes
- kubectl configured to access your cluster
- Helm 3.x installed

### Install NFS Client Tools

**IMPORTANT:** All Kubernetes nodes must have NFS client tools installed.

On each node, run:

```bash
sudo apt-get update
sudo apt-get install -y nfs-common
```

For RHEL/CentOS/Rocky:
```bash
sudo yum install -y nfs-utils
```

### Verify NFS Server Access

Before installing the provisioner, verify nodes can mount the NFS share:

```bash
# Test mount (run on a node)
sudo mkdir -p /mnt/test-nfs
sudo mount -t nfs <NFS_SERVER_IP>:<NFS_EXPORT_PATH> /mnt/test-nfs

# Check if mounted
df -h | grep test-nfs

# Unmount
sudo umount /mnt/test-nfs
```

## NFS Server Setup Example

If you need to set up an NFS server, here's a quick example for Ubuntu:

```bash
# Install NFS server
sudo apt-get install -y nfs-kernel-server

# Create export directory
sudo mkdir -p /mnt/nfs-share

# Set permissions (adjust as needed)
sudo chown nobody:nogroup /mnt/nfs-share
sudo chmod 777 /mnt/nfs-share

# Configure export
echo "/mnt/nfs-share 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports

# Apply configuration
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server

# Verify
sudo exportfs -v
```

**Security Note:** The example above uses permissive settings. For production:
- Use specific IP ranges or hostnames
- Consider `root_squash` instead of `no_root_squash`
- Use appropriate permissions (e.g., 755 instead of 777)
- Enable firewall rules to restrict NFS access

## Installation

### Step 1: Add Helm Repository

```bash
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner
helm repo update
```

### Step 2: Configure NFS Settings

Edit `custom-values.yaml` and replace the placeholder values:

```yaml
nfs:
  server: 10.0.0.2  # Your NFS server IP or hostname
  path: /mnt/user/k8s-data  # Your NFS export path
```

### Step 3: Install NFS Provisioner

```bash
helm upgrade --install nfs-subdir-external-provisioner \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace default \
  --version 4.0.18 \
  -f custom-values.yaml
```

**Note:** This chart can be installed in any namespace. The default namespace is used in this example.

### Step 4: Verify Installation

```bash
# Check pod status
kubectl get pods -l app=nfs-subdir-external-provisioner

# Check StorageClass
kubectl get storageclass nfs-client

# Verify provisioner is running
kubectl logs -l app=nfs-subdir-external-provisioner
```

You should see the `nfs-client` StorageClass created.

## Configuration

### Storage Class Settings

The provisioner creates a StorageClass named `nfs-client` with these settings:

```yaml
storageClass:
  create: true
  defaultClass: false  # Set to true to make it the default StorageClass
  name: nfs-client
  allowVolumeExpansion: true
  reclaimPolicy: Retain  # Keeps data when PVC is deleted
  archiveOnDelete: true  # Moves data to "archived-<pvc-name>" directory
  accessModes: ReadWriteMany
  volumeBindingMode: Immediate
```

#### Reclaim Policy Options

- **Retain**: When PVC is deleted, PV and data are kept (recommended for important data)
- **Delete**: When PVC is deleted, PV and data are removed

#### Archive on Delete

When `archiveOnDelete: true` and `reclaimPolicy: Delete`:
- PVC deletion moves data to `archived-<pvc-name>-<timestamp>` directory instead of deleting it
- Provides safety net against accidental data loss
- Archived directories must be manually cleaned up

### Mount Options

You can specify NFS mount options:

```yaml
nfs:
  mountOptions:
    - nfsvers=4.1
    - hard
    - timeo=600
    - retrans=2
```

Common options:
- `nfsvers=4.1`: Force NFSv4.1 (recommended)
- `hard`: Retry indefinitely if NFS server is unreachable
- `soft`: Give up after `retrans` retries (not recommended for production)
- `timeo=600`: Timeout in deciseconds (60 seconds)
- `noatime`: Don't update access times (performance improvement)

## Usage

### Creating a PVC with Dynamic Provisioning

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-nfs-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: nfs-client
  resources:
    requests:
      storage: 10Gi
```

Apply:
```bash
kubectl apply -f my-nfs-pvc.yaml

# Verify PVC is Bound
kubectl get pvc my-nfs-pvc
```

The provisioner will:
1. Create a subdirectory on the NFS share (e.g., `default-my-nfs-pvc-pvc-<uid>`)
2. Create a PersistentVolume
3. Bind the PVC to the PV

### Using the PVC in a Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  containers:
  - name: test-container
    image: nginx:latest
    volumeMounts:
    - name: nfs-storage
      mountPath: /usr/share/nginx/html
  volumes:
  - name: nfs-storage
    persistentVolumeClaim:
      claimName: my-nfs-pvc
```

### Shared Storage Example (Multiple Pods)

NFS supports ReadWriteMany, allowing multiple pods to use the same PVC:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shared-storage-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: shared-storage
  template:
    metadata:
      labels:
        app: shared-storage
    spec:
      containers:
      - name: app
        image: nginx:latest
        volumeMounts:
        - name: shared-data
          mountPath: /data
      volumes:
      - name: shared-data
        persistentVolumeClaim:
          claimName: my-nfs-pvc  # Same PVC used by all replicas
```

### Volume Expansion

To expand an existing volume:

```bash
# Edit the PVC
kubectl edit pvc my-nfs-pvc

# Change storage size (e.g., from 10Gi to 20Gi)
spec:
  resources:
    requests:
      storage: 20Gi

# Verify expansion
kubectl get pvc my-nfs-pvc
```

**Note:** The PVC size is informational only for NFS. The actual storage limit is determined by your NFS server's available space.

## Comparison with Manual NFS PVs

The parent `nfs-storage/` directory contains examples of manually created NFS PVs/PVCs. Here's when to use each approach:

### Use NFS Provisioner (Dynamic) When:
- You need many volumes
- Volumes are created/deleted frequently
- You want automatic subdirectory management
- You prefer Kubernetes-native provisioning

### Use Manual PVs When:
- You need specific NFS subdirectories
- You want full control over mount options per volume
- You're migrating existing NFS shares
- You need to share the same NFS path across multiple PVCs

### Migration from Manual PVs

If you have existing manual NFS PVs, you can keep them alongside the provisioner. They won't conflict.

To migrate to dynamic provisioning:
1. Create new PVC using `nfs-client` StorageClass
2. Copy data from old PV to new PV (using a migration pod)
3. Update applications to use new PVC
4. Delete old PVC and PV when migration is complete

## Troubleshooting

### 1. PVC Stuck in Pending

**Symptom:**
```bash
kubectl get pvc
# Shows STATUS: Pending
```

**Debug:**
```bash
# Check PVC events
kubectl describe pvc <pvc-name>

# Check provisioner logs
kubectl logs -l app=nfs-subdir-external-provisioner

# Verify StorageClass exists
kubectl get storageclass nfs-client
```

**Common causes:**
- NFS server unreachable from nodes
- nfs-common not installed on nodes
- Incorrect NFS server IP or path in custom-values.yaml
- NFS export permissions deny access

**Solutions:**
- Verify NFS server is running: `showmount -e <NFS_SERVER_IP>`
- Test mount from a node (see Prerequisites section)
- Check NFS server logs: `sudo journalctl -u nfs-server`
- Verify export configuration: `sudo exportfs -v`

### 2. Pod Stuck Creating Container

**Symptom:**
Pod using NFS PVC stuck in ContainerCreating state

**Debug:**
```bash
# Check pod events
kubectl describe pod <pod-name>

# Check node kubelet logs (on the node where pod is scheduled)
sudo journalctl -u kubelet -f
```

**Common causes:**
- Mount timeout (NFS server slow or unreachable)
- Permission denied on NFS export
- Stale NFS mount on node

**Solutions:**
- Verify NFS mount options in custom-values.yaml
- Check NFS server permissions (no_root_squash may be needed)
- Clean up stale mounts on node:
  ```bash
  # On the node
  sudo umount -l /var/lib/kubelet/pods/<pod-uid>/volumes/kubernetes.io~nfs/*
  ```

### 3. Permission Denied Errors

**Symptom:**
Application can't write to NFS volume

**Cause:** NFS export permissions or ownership mismatch

**Solutions:**

1. **Use no_root_squash in NFS exports** (if running as root):
   ```bash
   # On NFS server
   sudo nano /etc/exports
   # Add no_root_squash to export options
   /mnt/nfs-share 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)

   sudo exportfs -ra
   ```

2. **Match ownership** (if running as specific user):
   ```bash
   # On NFS server, set ownership to match pod's UID/GID
   sudo chown -R 1000:1000 /mnt/nfs-share/<subdirectory>
   ```

3. **Use securityContext in pod**:
   ```yaml
   securityContext:
     fsGroup: 1000
     runAsUser: 1000
     runAsGroup: 1000
   ```

### 4. Provisioner Pod CrashLoopBackOff

**Debug:**
```bash
kubectl logs -l app=nfs-subdir-external-provisioner
kubectl describe pod -l app=nfs-subdir-external-provisioner
```

**Common causes:**
- Invalid NFS server or path in values
- NFS server not reachable
- Missing RBAC permissions

**Solution:**
Verify and update custom-values.yaml, then upgrade Helm release:
```bash
helm upgrade nfs-subdir-external-provisioner \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace default \
  --version 4.0.18 \
  -f custom-values.yaml
```

### 5. Slow Performance

**Symptoms:**
- Slow file I/O
- Application timeouts
- High latency

**Causes & Solutions:**

1. **Network latency**: NFS is network-dependent
   - Use NFSv4.1 for better performance: `mountOptions: [nfsvers=4.1]`
   - Ensure NFS server and nodes are on same network segment
   - Use 10GbE network for heavy I/O workloads

2. **NFS server bottleneck**:
   - Check NFS server CPU/memory/disk
   - Consider faster storage on NFS server (SSD instead of HDD)
   - Tune NFS server settings (rsize, wsize)

3. **Mount options**:
   ```yaml
   nfs:
     mountOptions:
       - nfsvers=4.1
       - noatime  # Don't update access times
       - nodiratime  # Don't update directory access times
       - rsize=1048576  # 1MB read size
       - wsize=1048576  # 1MB write size
   ```

4. **Wrong use case**: NFS is not suitable for:
   - Database storage (use block storage like Longhorn)
   - High-IOPS applications
   - Applications requiring file locking (use with caution)

## Upgrading

### Check for Breaking Changes

Review the [NFS Provisioner changelog](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner/releases) before upgrading.

### Upgrade Helm Release

```bash
# Update repo
helm repo update

# Check new chart version
helm search repo nfs-subdir-external-provisioner

# Upgrade to new version
helm upgrade nfs-subdir-external-provisioner \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace default \
  --version <NEW_VERSION> \
  -f custom-values.yaml

# Verify
kubectl rollout status deployment/nfs-subdir-external-provisioner
```

**Note:** Upgrading the provisioner does not affect existing PVs/PVCs.

## Best Practices

### 1. Use Specific NFS Server

Avoid using hostnames that resolve to multiple IPs. Use a specific IP or dedicated hostname.

### 2. Enable Archive on Delete

Keep `archiveOnDelete: true` to protect against accidental data loss:

```yaml
storageClass:
  archiveOnDelete: true
  reclaimPolicy: Delete
```

### 3. Monitor NFS Server

- Set up monitoring for NFS server disk space
- Alert when NFS share is >80% full
- Monitor NFS server performance

### 4. Regular Backups

NFS provisioner doesn't provide backup functionality. Implement separate backup strategy:
- Use k8up for backup to S3
- Use rsync/rclone to backup NFS server
- Take NFS server snapshots (if supported by storage backend)

### 5. Test Failover

Test what happens when NFS server becomes unavailable:
- Pods may hang waiting for NFS
- Consider using `soft` mount option for non-critical data
- Implement health checks with appropriate timeouts

### 6. Limit Storage Usage

Since NFS doesn't enforce quota at the PVC level:
- Monitor actual disk usage
- Set application-level limits where possible
- Implement alerts for high NFS usage

### 7. Security Considerations

- Use NFSv4.1 for better security
- Restrict NFS exports to specific IP ranges
- Consider using Kerberos for NFS authentication (advanced)
- Encrypt data at rest on NFS server
- Use network policies to restrict access to provisioner pod

## Migration from k3s-ansible

- **Source:** `roles/kubernetes/nfs_client/`
- **Chart version:** v4.0.18 (unchanged)
- **Variables converted:**
  - `nfs_client_enabled` → Removed (deployment is manual)
  - `nfs_client_namespace` → Documented as `default` (can be changed)
  - `nfs_client_chart_version` → Documented in README (v4.0.18)
  - `nfs_client_server` → `CHANGE_ME_NFS_SERVER_IP` in custom-values.yaml
  - `nfs_client_path` → `CHANGE_ME_NFS_EXPORT_PATH` in custom-values.yaml

### Differences from Ansible Deployment

1. **Namespace:** k3s-ansible defaulted to `default`, manual deployment allows any namespace
2. **Values:** No changes to actual Helm values (just variable templating removed)
3. **Deployment:** Manual Helm install instead of Ansible automation

### Existing Manual PVs

The parent `nfs-storage/` directory contains manual NFS PV/PVC definitions used in your cluster. These can coexist with the NFS provisioner:

- **Manual PVs:** For specific, pre-defined NFS shares (e.g., media libraries)
- **NFS Provisioner:** For dynamic, application-managed storage

## Additional Resources

- [Official Documentation](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner)
- [Helm Chart Repository](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner/tree/master/charts/nfs-subdir-external-provisioner)
- [Kubernetes NFS Guide](https://kubernetes.io/docs/concepts/storage/volumes/#nfs)
- [NFS Server Setup Guide](https://ubuntu.com/server/docs/service-nfs)

## Quick Reference

```bash
# Install nfs-common on nodes
sudo apt-get install -y nfs-common

# Test NFS mount
sudo mount -t nfs <SERVER>:<PATH> /mnt/test

# Install provisioner
helm upgrade --install nfs-subdir-external-provisioner \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace default --version 4.0.18 -f custom-values.yaml

# Check provisioner
kubectl get pods -l app=nfs-subdir-external-provisioner
kubectl get storageclass nfs-client

# Create PVC
kubectl apply -f my-nfs-pvc.yaml

# Debug
kubectl describe pvc <pvc-name>
kubectl logs -l app=nfs-subdir-external-provisioner

# NFS server commands
showmount -e <NFS_SERVER>  # List exports
sudo exportfs -v  # Show current exports
sudo exportfs -ra  # Re-export all
```
