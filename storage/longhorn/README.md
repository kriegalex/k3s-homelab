# Longhorn - Distributed Block Storage for Kubernetes

## Overview

Longhorn is a lightweight, reliable, and powerful distributed block storage system for Kubernetes. It creates replicated volumes across cluster nodes, providing high availability and data redundancy for stateful applications.

**Key features:**
- Cloud-native distributed block storage built using microservices
- Incremental snapshot and backup to S3/NFS
- Volume replication across nodes for high availability
- Cross-cluster disaster recovery with automatic backups
- Built-in web UI for volume management
- Supports ReadWriteOnce (RWO) access mode
- Thin provisioning with overprovisioning support
- Easy upgrades and volume migrations

**Use cases:**
- Persistent storage for databases (PostgreSQL, MySQL, MongoDB)
- Stateful applications requiring high availability
- Media storage with replication
- Development/staging environments with snapshot/restore

## Prerequisites

- Kubernetes cluster (v1.21+)
- kubectl configured to access your cluster
- Helm 3.x installed
- **open-iscsi installed on all nodes** (critical requirement)
- At least 3 worker nodes (for replica count of 2-3)
- Sufficient disk space on each node for storage pool

### Installing open-iscsi on Nodes

**IMPORTANT:** Longhorn requires open-iscsi on all nodes. Without it, volumes will fail to attach to pods.

You need to run these commands **with sudo privileges** on each node:

#### Ubuntu/Debian:
```bash
sudo apt-get update
sudo apt-get install -y open-iscsi
sudo systemctl enable --now iscsid
```

#### RHEL/Rocky/Fedora:
```bash
sudo yum install -y iscsi-initiator-utils
sudo systemctl enable --now iscsid
```

#### Verify installation:
```bash
# Should return "active (running)"
sudo systemctl status iscsid
```

**Note:** You cannot execute sudo commands via automation tools. You must manually run these commands on each node or use configuration management tools like Ansible.

## Installation

### Step 1: Add Helm Repository

```bash
helm repo add longhorn https://charts.longhorn.io
helm repo update
```

### Step 2: Install Longhorn

```bash
helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --version 1.8.1-rc2 \
  -f custom-values.yaml
```

**Chart version note:** This deployment uses Longhorn 1.8.1-rc2. Check [Longhorn releases](https://github.com/longhorn/longhorn/releases) for the latest stable version.

### Step 3: Verify Installation

```bash
# Check pod status
kubectl get pods -n longhorn-system

# All pods should be Running (may take 2-3 minutes)
# - longhorn-manager (one per node)
# - longhorn-driver-deployer
# - longhorn-ui
# - csi-attacher
# - csi-provisioner
# - csi-resizer
# - csi-snapshotter
# - engine-image-ei-* (one per node)
# - instance-manager-* (created dynamically)

# Wait for all pods to be ready
kubectl wait --namespace longhorn-system \
  --for=condition=ready pod \
  --selector=app=longhorn-manager \
  --timeout=300s

# Verify storage class was created
kubectl get storageclass
# Should show "longhorn" (default) with provisioner "driver.longhorn.io"
```

### Step 4: Verify Node Readiness

```bash
# Check that all nodes are ready for Longhorn
kubectl get nodes -o wide

# Verify Longhorn detected all nodes
kubectl get nodes -n longhorn-system
```

## Configuration

The `custom-values.yaml` configures Longhorn with production-ready defaults.

### Storage Class Settings

```yaml
persistence:
  defaultClass: true                    # Makes Longhorn the default storage class
  defaultFsType: ext4                   # Filesystem for volumes (ext4 or xfs)
  defaultClassReplicaCount: 2           # Number of replicas per volume
  defaultDataLocality: disabled         # Data locality policy
  reclaimPolicy: "Delete"               # Delete volumes when PVC is deleted
```

**Reclaim Policy:**
- `Delete`: Automatically deletes volume when PVC is deleted (default, saves space)
- `Retain`: Keeps volume after PVC deletion (for critical data, manual cleanup required)

**Replica Count:**
- `1`: No redundancy (data loss if node fails) - development only
- `2`: Tolerates 1 node failure (recommended for small clusters)
- `3`: Tolerates 2 node failures (recommended for production)

**Data Locality:**
- `disabled`: Replicas distributed across nodes (default, best for HA)
- `best-effort`: Tries to keep one replica on the same node as the pod
- `strict`: Requires one replica on the pod's node (faster but less flexible)

### Default Settings

```yaml
defaultSettings:
  defaultReplicaCount: 2
  # backupTarget: "s3://bucket-name@region/"
  # backupTargetCredentialSecret: "minio-bucket-credentials"
```

**Important settings:**
- `defaultReplicaCount`: Global default for all volumes (can be overridden per PVC)
- `backupTarget`: S3/NFS URL for backups (uncomment to enable)
- `backupTargetCredentialSecret`: Secret with S3 credentials

### Network Policies

```yaml
networkPolicies:
  enabled: false
  type: "k3s"
```

Set `enabled: true` if using Kubernetes network policies. The `type: "k3s"` optimizes for k3s clusters.

### Ingress Configuration

```yaml
ingress:
  enabled: false                        # Set to true to expose UI via ingress
  ingressClassName: nginx
  host: longhorn.yourdomain.com         # CHANGE_ME
  tls: false                            # Set to true to enable TLS
  tlsSecret: longhorn-tls
  path: /
  annotations: {}
    # cert-manager.io/cluster-issuer: "letsencrypt-prod"
```

**Note:** We recommend using the separate `ingress-longhorn-ui.yaml` manifest instead of Helm ingress for better control.

## Usage

### Creating Persistent Volume Claims

Longhorn automatically provisions volumes when you create a PVC.

**Example PVC:**

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-app-data
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn  # Uses Longhorn storage
  resources:
    requests:
      storage: 10Gi
```

Apply and verify:

```bash
kubectl apply -f pvc.yaml

# Check PVC status
kubectl get pvc my-app-data
# Should show STATUS: Bound

# Check corresponding PV
kubectl get pv
```

### Using Longhorn as Default Storage Class

Longhorn is configured as the default storage class, so you can omit `storageClassName`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-app-data
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  # storageClassName is optional (uses default: longhorn)
```

### Volume with Custom Replica Count

Override the default replica count for specific volumes:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: critical-data
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 20Gi
---
apiVersion: longhorn.io/v1beta2
kind: Volume
metadata:
  name: critical-data
  namespace: longhorn-system
spec:
  numberOfReplicas: 3  # Override default (usually 2)
  dataLocality: disabled
  size: 21474836480    # 20Gi in bytes
```

### Using Longhorn Volumes in Pods

Reference the PVC in your pod/deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: app
        image: myapp:latest
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: my-app-data  # References the PVC
```

## S3 Backup Setup

Longhorn supports automated backups to S3-compatible storage (AWS S3, MinIO, etc.).

### Step 1: Create S3 Credentials Secret

```bash
# Copy the secrets template
cp secrets-template.yaml secrets.yaml

# Edit secrets.yaml and configure:
# - AWS_ACCESS_KEY_ID
# - AWS_SECRET_ACCESS_KEY
# - AWS_ENDPOINTS (for MinIO/S3-compatible storage)
nano secrets.yaml

# Apply the secret
kubectl apply -f secrets.yaml
```

**For AWS S3:**
```yaml
stringData:
  AWS_ACCESS_KEY_ID: "AKIAIOSFODNN7EXAMPLE"
  AWS_SECRET_ACCESS_KEY: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
  AWS_ENDPOINTS: ""  # Leave empty for AWS S3
```

**For MinIO:**
```yaml
stringData:
  AWS_ACCESS_KEY_ID: "minio-access-key"
  AWS_SECRET_ACCESS_KEY: "minio-secret-key"
  AWS_ENDPOINTS: "http://minio.default.svc.cluster.local:9000"
```

### Step 2: Configure Backup Target

Edit `custom-values.yaml` and uncomment the backup settings:

```yaml
defaultSettings:
  defaultReplicaCount: 2
  backupTarget: "s3://my-bucket@us-east-1/"  # For AWS S3
  # backupTarget: "s3://longhorn-backups@ch-fr-1/"  # For MinIO (region can be arbitrary)
  backupTargetCredentialSecret: "minio-bucket-credentials"
```

**Backup target format:**
- AWS S3: `s3://bucket-name@region/`
- MinIO: `s3://bucket-name@region/` (region can be any value, e.g., "us-east-1")
- NFS: `nfs://nfs-server:/path/to/backups`

Apply the updated configuration:

```bash
helm upgrade longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --version 1.8.1-rc2 \
  -f custom-values.yaml
```

### Step 3: Create Recurring Backup Jobs

Create recurring backups via the Longhorn UI or with a RecurringJob resource:

```yaml
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: backup-daily
  namespace: longhorn-system
spec:
  cron: "0 2 * * *"        # Daily at 2 AM
  task: "backup"           # or "snapshot" for local snapshots
  groups:
    - default              # Apply to all volumes with group "default"
  retain: 7                # Keep 7 backups
  concurrency: 2           # Run 2 backups in parallel
  labels:
    schedule: daily
```

Apply and verify:

```bash
kubectl apply -f recurring-backup.yaml

# Check recurring jobs
kubectl get recurringjob -n longhorn-system

# Assign volume to backup group (via UI or Volume spec)
```

### Step 4: Manual Backup

Trigger a manual backup via Longhorn UI:

1. Go to Volume → Select volume → Create Backup
2. Monitor backup progress in Backup tab
3. View backups in S3 bucket

Or use kubectl:

```bash
# Create backup of a specific volume
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Backup
metadata:
  name: my-app-data-backup-$(date +%Y%m%d)
  namespace: longhorn-system
spec:
  snapshotName: backup-$(date +%Y%m%d-%H%M%S)
  labels:
    purpose: manual-backup
EOF
```

### Step 5: Restore from Backup

Restore a volume from S3 backup:

1. Go to Backup tab in Longhorn UI
2. Select backup → Restore
3. Choose restore options:
   - Create new volume (new PV/PVC)
   - Restore to existing volume (overwrites data)
4. Monitor restore progress

Or via kubectl:

```yaml
apiVersion: longhorn.io/v1beta2
kind: Volume
metadata:
  name: restored-volume
  namespace: longhorn-system
spec:
  fromBackup: "s3://my-bucket@us-east-1/backups/backup-abc123"
  numberOfReplicas: 2
  size: 10737418240  # 10Gi
```

## UI Access

### Option 1: Port-Forward (Quick Access)

```bash
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80

# Access at: http://localhost:8080
```

### Option 2: Ingress with TLS (Production)

Edit `ingress-longhorn-ui.yaml`:

```yaml
spec:
  tls:
  - hosts:
    - longhorn.yourdomain.com  # CHANGE_ME
    secretName: longhorn-ui-tls
  rules:
  - host: longhorn.yourdomain.com  # CHANGE_ME
```

Apply the ingress:

```bash
kubectl apply -f ingress-longhorn-ui.yaml

# Verify ingress
kubectl get ingress -n longhorn-system

# Access at: https://longhorn.yourdomain.com
```

**Security recommendation:** Add authentication to the ingress (basic auth, oauth2-proxy, etc.):

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: longhorn-basic-auth
    nginx.ingress.kubernetes.io/auth-realm: 'Authentication Required'
```

Create basic auth secret:

```bash
htpasswd -c auth admin
kubectl create secret generic longhorn-basic-auth \
  --from-file=auth \
  -n longhorn-system
```

### UI Features

The Longhorn dashboard provides:
- **Volume management:** Create, attach, detach, delete volumes
- **Snapshots:** Create point-in-time snapshots
- **Backups:** Manage S3/NFS backups and restores
- **Node management:** View node disk usage and status
- **Settings:** Configure global Longhorn settings
- **Recurring jobs:** Manage automated snapshot/backup schedules

## Troubleshooting

### 1. Volume Stuck in "Pending" State

**Symptom:**
```bash
kubectl get pvc
# Shows STATUS: Pending
```

**Debug:**
```bash
# Describe PVC
kubectl describe pvc <pvc-name> -n <namespace>

# Check Longhorn manager logs
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=100

# Check node disk space
kubectl get nodes -o wide
df -h  # On each node
```

**Common causes:**
- Insufficient disk space on nodes
- open-iscsi not installed on nodes
- Node not detected by Longhorn
- All nodes cordoned or tainted

**Solutions:**
```bash
# Verify open-iscsi on all nodes (requires sudo on each node)
sudo systemctl status iscsid

# Check Longhorn node status
kubectl get nodes -n longhorn-system -o wide

# Check node disk space (via Longhorn UI or kubectl)
kubectl get node -n longhorn-system -o yaml
```

### 2. Pod Stuck in "ContainerCreating" with Volume Attach Errors

**Symptom:**
```bash
kubectl get pods
# Shows STATUS: ContainerCreating for extended period

kubectl describe pod <pod-name>
# Events show: "Unable to attach or mount volumes"
```

**Debug:**
```bash
# Check volume attachment status
kubectl get volumeattachment

# Check Longhorn volume state
kubectl get volumes -n longhorn-system

# Check instance manager pods
kubectl get pods -n longhorn-system | grep instance-manager

# Check for errors in Longhorn logs
kubectl logs -n longhorn-system -l app=longhorn-manager | grep -i error
```

**Common causes:**
- Volume attached to wrong node
- Instance manager pod not running
- open-iscsi service stopped on node
- Stale volume attachments

**Solutions:**
```bash
# Detach volume manually via Longhorn UI:
# Volume → Select volume → Detach

# Restart instance manager (if failed)
kubectl delete pod -n longhorn-system <instance-manager-pod>

# Verify iscsid service (requires sudo on affected node)
sudo systemctl restart iscsid
```

### 3. Backup Failures

**Symptom:**
Backup job shows "Error" status in Longhorn UI

**Debug:**
```bash
# Check backup status
kubectl get backups -n longhorn-system

# Describe backup
kubectl describe backup <backup-name> -n longhorn-system

# Check Longhorn manager logs for S3 errors
kubectl logs -n longhorn-system -l app=longhorn-manager | grep -i backup
```

**Common causes:**
- Invalid S3 credentials
- S3 bucket doesn't exist
- Network connectivity to S3 endpoint
- Insufficient permissions on S3 bucket

**Solutions:**
```bash
# Verify secret exists and is correct
kubectl get secret minio-bucket-credentials -n longhorn-system -o yaml

# Test S3 connectivity from a pod
kubectl run -it --rm debug --image=amazon/aws-cli --restart=Never -- \
  s3 ls s3://bucket-name --endpoint-url=http://minio:9000

# Update backup target credentials
kubectl delete secret minio-bucket-credentials -n longhorn-system
kubectl apply -f secrets.yaml
```

### 4. Performance Issues

**Symptom:**
- Slow I/O performance
- High latency in applications using Longhorn volumes

**Debug:**
```bash
# Check node disk I/O
kubectl get nodes -o wide
# SSH to node and run:
iostat -x 5 3

# Check volume replica count and distribution
kubectl get volumes -n longhorn-system -o wide

# Check for network issues between nodes
# Test with iperf3 between nodes
```

**Common causes:**
- High replica count on slow disks
- Network bandwidth limitations
- CPU/memory pressure on nodes
- Disk fragmentation

**Solutions:**
- Reduce replica count for non-critical volumes
- Use faster disks (SSD instead of HDD)
- Increase node resources (CPU/memory)
- Enable data locality for performance-sensitive workloads:
  ```yaml
  apiVersion: longhorn.io/v1beta2
  kind: Volume
  metadata:
    name: fast-volume
  spec:
    dataLocality: best-effort  # or strict
  ```

### 5. Node Disk Full

**Symptom:**
```bash
# Longhorn UI shows node disk usage at 100%
# New volumes fail to provision
```

**Debug:**
```bash
# Check disk usage on nodes
kubectl get nodes -n longhorn-system -o yaml | grep -A 10 diskStatus

# Check volume sizes
kubectl get pv -o custom-columns=NAME:.metadata.name,SIZE:.spec.capacity.storage,STORAGECLASS:.spec.storageClassName

# Find large volumes
kubectl get volumes -n longhorn-system -o custom-columns=NAME:.metadata.name,SIZE:.spec.size,REPLICAS:.spec.numberOfReplicas
```

**Solutions:**
```bash
# Delete unused PVCs
kubectl get pvc -A | grep -v Bound
kubectl delete pvc <unused-pvc> -n <namespace>

# Clean up old backups (via UI or kubectl)
kubectl delete backup <old-backup> -n longhorn-system

# Reduce replica count for large volumes
# (via Longhorn UI: Volume → Update Replicas)

# Add more storage to nodes (expand disks)
```

### 6. Volume Degraded (Replica Failures)

**Symptom:**
Volume shows "Degraded" status in Longhorn UI

**Debug:**
```bash
# Check volume status
kubectl get volumes -n longhorn-system

# Describe volume to see replica status
kubectl describe volume <volume-name> -n longhorn-system

# Check for failed replicas
kubectl get replicas -n longhorn-system | grep -i failed
```

**Common causes:**
- Node failure or maintenance
- Disk failure
- Network partition
- Insufficient disk space

**Solutions:**
```bash
# Wait for automatic rebuild (Longhorn rebuilds replicas automatically)

# Force rebuild via UI:
# Volume → Manage Replicas → Remove failed replica
# Longhorn creates a new replica automatically

# If node is permanently down, cordon it
kubectl cordon <node-name>
# Longhorn redistributes replicas to healthy nodes
```

### 7. Upgrade Issues

**Symptom:**
Longhorn upgrade fails or volumes become unavailable

**Debug:**
```bash
# Check Longhorn component versions
kubectl get pods -n longhorn-system -o wide

# Check upgrade status
kubectl logs -n longhorn-system deployment/longhorn-driver-deployer

# Check for incompatible settings
kubectl get settings -n longhorn-system -o yaml
```

**Solutions:**
```bash
# Follow upgrade procedure strictly (see Upgrading section)
# Never skip versions (upgrade incrementally)

# Rollback if upgrade fails
helm rollback longhorn -n longhorn-system

# Check compatibility matrix before upgrading
# https://longhorn.io/docs/latest/deploy/upgrade/
```

## Upgrading

**IMPORTANT:** Always backup your data before upgrading Longhorn.

### Pre-Upgrade Checklist

1. **Review release notes:** [Longhorn releases](https://github.com/longhorn/longhorn/releases)
2. **Check compatibility:** Ensure Kubernetes version is supported
3. **Backup volumes:** Create S3 backups of critical volumes
4. **Take snapshots:** Create snapshots of all volumes via UI
5. **Export configuration:** Backup Longhorn settings
   ```bash
   kubectl get settings -n longhorn-system -o yaml > longhorn-settings-backup.yaml
   ```

### Upgrade Procedure

```bash
# 1. Backup current Helm values
helm get values longhorn -n longhorn-system > longhorn-values-backup.yaml

# 2. Update Helm repository
helm repo update

# 3. Check available versions
helm search repo longhorn/longhorn --versions

# 4. Upgrade to new version
helm upgrade longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --version <NEW_VERSION> \
  -f custom-values.yaml

# 5. Monitor upgrade progress
kubectl get pods -n longhorn-system -w

# 6. Verify all components are running
kubectl wait --namespace longhorn-system \
  --for=condition=ready pod \
  --selector=app=longhorn-manager \
  --timeout=600s

# 7. Check volumes are healthy
kubectl get volumes -n longhorn-system
# All should show "Healthy"

# 8. Verify via UI
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
# Access http://localhost:8080 and check Dashboard
```

### Post-Upgrade Verification

```bash
# Check all PVCs are still bound
kubectl get pvc -A | grep longhorn

# Restart pods using Longhorn volumes (if recommended by release notes)
kubectl rollout restart deployment/<app-deployment> -n <namespace>

# Test volume provisioning
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-upgrade
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
EOF

kubectl get pvc test-upgrade
# Should show Bound

# Cleanup test
kubectl delete pvc test-upgrade
```

### Rollback Procedure (If Upgrade Fails)

```bash
# List Helm release history
helm history longhorn -n longhorn-system

# Rollback to previous version
helm rollback longhorn -n longhorn-system

# Monitor rollback
kubectl get pods -n longhorn-system -w

# Verify volumes are accessible
kubectl get pvc -A
```

## Best Practices

### 1. Use Appropriate Replica Counts

- **Development:** Replica count 1 (no redundancy, saves resources)
- **Staging:** Replica count 2 (tolerates 1 node failure)
- **Production:** Replica count 3 (tolerates 2 node failures)

### 2. Monitor Disk Usage

Set up alerts for node disk usage:

```bash
# Check disk usage regularly
kubectl get nodes -n longhorn-system -o yaml | grep -A 10 diskStatus

# Configure disk space thresholds in Longhorn settings:
# - Storage Over Provisioning Percentage: 200% (default)
# - Storage Minimal Available Percentage: 25% (default)
```

### 3. Regular Backups

- Enable recurring backups for critical volumes
- Test restore procedure regularly
- Store backups in a different location (S3 in different region)
- Keep at least 7-30 daily backups

### 4. Volume Snapshots Before Changes

Create snapshots before:
- Application upgrades
- Database migrations
- Major configuration changes

```bash
# Create snapshot via UI or kubectl
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Snapshot
metadata:
  name: pre-upgrade-snapshot
  namespace: longhorn-system
spec:
  volume: my-app-data
EOF
```

### 5. Secure UI Access

Always protect the Longhorn UI:
- Use ingress with TLS (cert-manager)
- Add authentication (basic auth, OAuth2 proxy, VPN)
- Restrict access to admin users only
- Never expose UI directly to the internet without authentication

### 6. Use Taints and Tolerations for Storage Nodes

Dedicate specific nodes for storage workloads:

```yaml
# Taint storage nodes
kubectl taint nodes storage-node-1 storage=longhorn:NoSchedule

# Configure Longhorn to tolerate storage taint
longhornManager:
  tolerations:
  - key: storage
    operator: Equal
    value: longhorn
    effect: NoSchedule
```

### 7. Monitor Volume Health

Use Longhorn's monitoring capabilities:
- Enable Prometheus metrics export
- Set up Grafana dashboards for Longhorn
- Alert on degraded volumes
- Track backup success/failure rates

### 8. Plan for Growth

- Monitor storage growth trends
- Add nodes/disks before reaching capacity
- Use storage overprovisioning carefully
- Archive old data to object storage

## Migration from k3s-ansible

- **Source:** `roles/kubernetes/longhorn/`
- **Chart version:** 1.8.1-rc2 (updated from 1.6.x in k3s-ansible)
- **Variables converted:**
  - `longhorn_enabled` → Removed (deployment is manual)
  - `longhorn_namespace` → Documented as `longhorn-system`
  - `longhorn_chart_version` → Documented in README (1.8.1-rc2)
  - `longhorn_reclaim_policy` → `persistence.reclaimPolicy` in custom-values.yaml
  - `longhorn_dashboard_enabled` → `ingress.enabled` in custom-values.yaml
  - `longhorn_minio_backup_enabled` → `defaultSettings.backupTarget` in custom-values.yaml
  - `longhorn_minio_endpoint` → S3 endpoint in secrets.yaml
  - `longhorn_minio_backup_key` → `AWS_ACCESS_KEY_ID` in secrets.yaml
  - `longhorn_minio_backup_secret` → `AWS_SECRET_ACCESS_KEY` in secrets.yaml
  - `longhorn_minio_bucket_name` → Part of `backupTarget` URL
  - `longhorn_minio_region` → Part of `backupTarget` URL

### New Features in Migration

1. **Updated Chart Version:** Using 1.8.1-rc2 (latest features and bug fixes)
2. **Separate Ingress Manifest:** Better control over UI exposure vs Helm ingress
3. **Secrets Template:** Structured template for S3/MinIO credentials
4. **Comprehensive Configuration:** Extended custom-values.yaml with production settings
5. **Detailed Troubleshooting:** Step-by-step debugging for common issues
6. **Backup/Restore Guide:** Complete S3 backup setup and restore procedures

### Differences from k3s-ansible Deployment

| Aspect | k3s-ansible | k8s-homelab |
|--------|-------------|-------------|
| Deployment | Automated via Ansible | Manual Helm install |
| Configuration | Ansible variables | Helm values file |
| Secrets | Ansible Vault | Kubernetes secrets |
| Ingress | Template-based | Separate manifest |
| Dashboard | Auto-configured | Manual ingress setup |
| Backup Setup | Automated | Manual S3 config |
| Documentation | Basic vars | Comprehensive README |

## Additional Resources

- [Official Documentation](https://longhorn.io/docs/)
- [Helm Chart Repository](https://github.com/longhorn/charts)
- [GitHub Repository](https://github.com/longhorn/longhorn)
- [Best Practices Guide](https://longhorn.io/docs/latest/best-practices/)
- [Troubleshooting Guide](https://longhorn.io/docs/latest/troubleshooting/)
- [Monitoring Guide](https://longhorn.io/docs/latest/monitoring/)
- [Backup and Restore](https://longhorn.io/docs/latest/snapshots-and-backups/)
- [Disaster Recovery](https://longhorn.io/docs/latest/advanced-resources/disaster-recovery/)
- [Performance Tuning](https://longhorn.io/docs/latest/advanced-resources/performance/)

## Quick Reference

### Common Commands

```bash
# List all volumes
kubectl get volumes -n longhorn-system

# List all PVCs using Longhorn
kubectl get pvc -A | grep longhorn

# Check storage class
kubectl get storageclass longhorn -o yaml

# View Longhorn settings
kubectl get settings -n longhorn-system

# Create manual snapshot
kubectl apply -f snapshot.yaml

# Create manual backup
kubectl apply -f backup.yaml

# List backups
kubectl get backups -n longhorn-system

# Port-forward to UI
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80

# Check node disk status
kubectl get nodes -n longhorn-system -o yaml | grep -A 10 diskStatus

# Restart Longhorn manager (if needed)
kubectl rollout restart deployment/longhorn-driver-deployer -n longhorn-system
```

### Volume States

- **Detached:** Volume not attached to any node (normal for unused PVC)
- **Attached:** Volume attached to a node (pod is using it)
- **Healthy:** All replicas are healthy and running
- **Degraded:** One or more replicas are failed (rebuilding in progress)
- **Faulted:** Volume is inaccessible (critical issue)

### Backup Target Formats

```bash
# AWS S3
s3://bucket-name@region/

# MinIO (S3-compatible)
s3://bucket-name@us-east-1/  # Region can be arbitrary

# NFS
nfs://nfs-server-ip:/export/path
```
