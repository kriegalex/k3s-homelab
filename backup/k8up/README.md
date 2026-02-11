# k8up Backup Operator Installation Guide

k8up is a Kubernetes operator for backup and restore operations using Restic. It provides automated backups of PersistentVolumeClaims and databases to S3-compatible storage with retention policies and scheduled backups.

## Table of Contents

- [Prerequisites](#prerequisites)
- [What is k8up?](#what-is-k8up)
- [Installation](#installation)
- [Setup Backup Secrets](#setup-backup-secrets)
- [PVC Backups](#pvc-backups)
- [Database Backups](#database-backups)
- [Scheduled Backups](#scheduled-backups)
- [Restore Operations](#restore-operations)
- [Retention and Pruning](#retention-and-pruning)
- [Monitoring Backups](#monitoring-backups)
- [Troubleshooting](#troubleshooting)
- [Migration from k3s-ansible](#migration-from-k3s-ansible)

## Prerequisites

- Kubernetes cluster v1.23+ with kubectl configured
- Helm 3.0+
- S3-compatible storage (AWS S3, MinIO, Wasabi, Backblaze B2, etc.)
- S3 credentials (access key and secret key)
- Storage provisioner for PVCs

## NFS Backup Storage

Apply NFS volume for k8up backup repository:

```fish
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/backup/k8up/nfs/nfs-backup.yaml
```

See [k8up NFS README](nfs/README.md) for details.

## What is k8up?

k8up is a **Kubernetes operator** that automates backup and restore operations using Restic. It provides:

- **Automated PVC Backups**: Backup PersistentVolumeClaims to S3-compatible storage
- **Database Backups**: Execute commands (pg_dump, mysqldump) and backup output
- **Scheduled Backups**: Cron-based backup schedules with retention policies
- **Point-in-Time Recovery**: Restore specific snapshots
- **Pruning**: Automatic cleanup of old backups
- **Monitoring**: Prometheus metrics and Kubernetes events

### How It Works

1. **k8up Operator**: Watches for Backup, Restore, and Schedule CRDs
2. **Restic**: Open-source backup tool that encrypts and deduplicates data
3. **S3 Storage**: Backup destination (AWS S3, MinIO, etc.)
4. **Annotations**: Mark resources for backup using `k8up.io/backup` annotation

### Comparison with Velero

| Feature | k8up | Velero |
|---------|------|--------|
| Backup Scope | PVCs and pod commands | Full cluster state |
| Storage Backend | S3 only (via Restic) | Multiple providers |
| Complexity | Lower | Higher |
| Kubernetes Resources | No | Yes (CRDs, ConfigMaps, etc.) |
| Database Backups | Via annotations | Via plugins |
| Best For | Data backups | Disaster recovery |

## Installation

### Step 1: Add Helm Repository

```bash
helm repo add k8up-io https://k8up-io.github.io/k8up
helm repo update
```

### Step 2: Install k8up CRDs

k8up requires Custom Resource Definitions to be installed separately.

```bash
# Download CRDs
kubectl apply -f https://github.com/k8up-io/k8up/releases/download/k8up-4.8.3/k8up-crd.yaml

# Verify CRDs
kubectl get crd | grep k8up.io
```

Expected CRDs:
- backups.k8up.io
- checks.k8up.io
- prunes.k8up.io
- restores.k8up.io
- schedules.k8up.io

### Step 3: Install k8up Operator

```bash
# Create namespace
kubectl create namespace k8up-system

# Install operator
helm upgrade --install k8up k8up-io/k8up \
  --namespace k8up-system \
  --create-namespace \
  -f custom-values.yaml \
  --version 4.8.3
```

### Step 4: Verify Installation

```bash
# Check operator pod
kubectl get pods -n k8up-system

# Check operator logs
kubectl logs -n k8up-system -l app.kubernetes.io/name=k8up
```

## Setup Backup Secrets

Before backing up, create secrets for S3 credentials and Restic encryption password.

### Step 1: Copy Secrets Template

```bash
cp secrets-template.yaml secrets.yaml
```

### Step 2: Generate Restic Password

```bash
# Generate strong password for Restic repository encryption
openssl rand -base64 32
```

IMPORTANT: Save this password securely! Without it, you cannot restore backups.

### Step 3: Configure S3 Credentials

Edit `secrets.yaml` with your S3 credentials:

```yaml
stringData:
  username: "your-s3-access-key"
  password: "your-s3-secret-key"
  # For Restic password:
  password: "your-generated-restic-password"
```

### Step 4: Apply Secrets

```bash
# Apply to default namespace
kubectl apply -f secrets.yaml

# Or apply to specific namespace
kubectl apply -f secrets.yaml -n production
```

Verify secrets:

```bash
kubectl get secret minio-credentials backup-repo -n default
```

## PVC Backups

k8up backs up PVCs by mounting them and using Restic to upload data to S3.

### Manual PVC Backup

```bash
# Annotate PVC for backup
kubectl annotate pvc my-app-data k8up.io/backup=true -n default

# Trigger backup
kubectl apply -f - <<EOF
apiVersion: k8up.io/v1
kind: Backup
metadata:
  name: my-app-backup
  namespace: default
spec:
  backend:
    repoPasswordSecretRef:
      name: backup-repo
      key: password
    s3:
      endpoint: "http://minio.minio.svc.cluster.local:9000"
      bucket: "my-app-backups"
      accessKeyIDSecretRef:
        name: minio-credentials
        key: username
      secretAccessKeySecretRef:
        name: minio-credentials
        key: password
  podSecurityContext:
    runAsUser: 1000
    fsGroup: 1000
EOF
```

### Check Backup Status

```bash
# Watch backup progress
kubectl get backup my-app-backup -n default -w

# Check backup details
kubectl describe backup my-app-backup -n default

# View backup logs
kubectl logs -n default -l job-name=backup-my-app-backup-0
```

### Best Practices for PVC Backups

1. **Scale Down Applications**: Stop writes during backup to ensure consistency
   ```bash
   kubectl scale deployment my-app --replicas=0 -n default
   # Perform backup
   kubectl scale deployment my-app --replicas=1 -n default
   ```

2. **Use Correct User ID**: Set `runAsUser` to match PVC file ownership
   ```bash
   # Find PVC ownership
   kubectl exec my-app-pod -n default -- ls -ln /data
   # Use that UID in podSecurityContext
   ```

3. **Annotate Only What You Need**: With `BACKUP_SKIP_WITHOUT_ANNOTATION=true`, only annotated resources are backed up

## Database Backups

k8up can backup databases by executing dump commands inside pods.

### PostgreSQL Backup Example

```bash
# Annotate PostgreSQL pod
kubectl annotate pod postgres-0 -n default \
  k8up.io/backupcommand="sh -c 'PGDATABASE=\$POSTGRES_DB PGUSER=\$POSTGRES_USER PGPASSWORD=\$POSTGRES_PASSWORD pg_dump --clean'" \
  k8up.io/file-extension=".sql"

# Trigger backup
kubectl apply -f - <<EOF
apiVersion: k8up.io/v1
kind: Backup
metadata:
  name: postgres-backup
  namespace: default
spec:
  backend:
    repoPasswordSecretRef:
      name: backup-repo
      key: password
    s3:
      endpoint: "http://minio.minio.svc.cluster.local:9000"
      bucket: "postgres-backups"
      accessKeyIDSecretRef:
        name: minio-credentials
        key: username
      secretAccessKeySecretRef:
        name: minio-credentials
        key: password
  podSecurityContext:
    runAsUser: 999  # PostgreSQL user
EOF
```

### CloudNativePG Backup

```bash
# Annotate CNPG cluster primary pod
kubectl annotate pod myapp-cluster-1 -n default \
  k8up.io/backupcommand="sh -c 'pg_dumpall --clean --if-exists --username=postgres'" \
  k8up.io/file-extension=".sql"

# Trigger backup (use runAsUser: 26 for CNPG)
kubectl apply -f example-backup.yaml
```

### MySQL/MariaDB Backup

```bash
# Annotate MySQL pod
kubectl annotate pod mysql-0 -n default \
  k8up.io/backupcommand="sh -c 'mysqldump --all-databases --user=\$MYSQL_USER --password=\$MYSQL_PASSWORD'" \
  k8up.io/file-extension=".sql"

# Trigger backup with MySQL user ID (999 or 1001 depending on image)
```

### Database Backup Best Practices

1. **Use pg_dumpall for Multiple Databases**: Captures all databases, users, and roles
2. **Include --clean Flag**: Drops objects before recreating them during restore
3. **Verify Dump Command**: Test manually first:
   ```bash
   kubectl exec postgres-0 -n default -- \
     sh -c 'PGDATABASE=$POSTGRES_DB PGUSER=$POSTGRES_USER PGPASSWORD=$POSTGRES_PASSWORD pg_dump --clean'
   ```
4. **Remove Annotations After Backup**: Cleanup to avoid accidental future backups

## Scheduled Backups

Automate backups with Schedule CRDs using cron syntax.

### Create Daily Backup Schedule

```bash
kubectl apply -f - <<EOF
apiVersion: k8up.io/v1
kind: Schedule
metadata:
  name: daily-backup
  namespace: default
spec:
  backup:
    schedule: "0 2 * * *"  # Daily at 2:00 AM
    keepJobs: 14
    backend:
      repoPasswordSecretRef:
        name: backup-repo
        key: password
      s3:
        endpoint: "http://minio.minio.svc.cluster.local:9000"
        bucket: "scheduled-backups"
        accessKeyIDSecretRef:
          name: minio-credentials
          key: username
        secretAccessKeySecretRef:
          name: minio-credentials
          key: password
    podSecurityContext:
      runAsUser: 1000

  # Prune old backups weekly
  prune:
    schedule: "0 3 * * 0"  # Sunday at 3:00 AM
    retention:
      keepLast: 5
      keepDaily: 14
      keepWeekly: 4
      keepMonthly: 12
    backend:
      repoPasswordSecretRef:
        name: backup-repo
        key: password
      s3:
        endpoint: "http://minio.minio.svc.cluster.local:9000"
        bucket: "scheduled-backups"
        accessKeyIDSecretRef:
          name: minio-credentials
          key: username
        secretAccessKeySecretRef:
          name: minio-credentials
          key: password

  # Check backup integrity weekly
  check:
    schedule: "0 4 * * 0"  # Sunday at 4:00 AM
    backend:
      repoPasswordSecretRef:
        name: backup-repo
        key: password
      s3:
        endpoint: "http://minio.minio.svc.cluster.local:9000"
        bucket: "scheduled-backups"
        accessKeyIDSecretRef:
          name: minio-credentials
          key: username
        secretAccessKeySecretRef:
          name: minio-credentials
          key: password
EOF
```

### Cron Schedule Examples

```bash
# Every 6 hours
"0 */6 * * *"

# Daily at 2:30 AM
"30 2 * * *"

# Weekly on Sunday at 3:00 AM
"0 3 * * 0"

# Monthly on 1st at 4:00 AM
"0 4 1 * *"

# Every weekday at 1:00 AM
"0 1 * * 1-5"
```

### Manage Schedules

```bash
# List schedules
kubectl get schedule -n default

# Suspend a schedule (without deleting)
kubectl patch schedule daily-backup -n default \
  --type='json' -p='[{"op": "replace", "path": "/spec/suspend", "value": true}]'

# Resume schedule
kubectl patch schedule daily-backup -n default \
  --type='json' -p='[{"op": "replace", "path": "/spec/suspend", "value": false}]'

# Delete schedule
kubectl delete schedule daily-backup -n default
```

## Restore Operations

Restore backups to PVCs for recovery.

### List Available Snapshots

Before restoring, list available snapshots:

```bash
# Run Restic in a pod to list snapshots
kubectl run restic-list --rm -it --image=restic/restic --restart=Never -- \
  -r s3:http://minio.minio.svc.cluster.local:9000/my-app-backups \
  snapshots

# Enter Restic password when prompted (from backup-repo secret)
kubectl get secret backup-repo -n default -o jsonpath='{.data.password}' | base64 -d
```

### Restore Latest Backup

```bash
# Scale down application
kubectl scale deployment my-app --replicas=0 -n default

# Trigger restore
kubectl apply -f - <<EOF
apiVersion: k8up.io/v1
kind: Restore
metadata:
  name: my-app-restore
  namespace: default
spec:
  backend:
    repoPasswordSecretRef:
      name: backup-repo
      key: password
    s3:
      endpoint: "http://minio.minio.svc.cluster.local:9000"
      bucket: "my-app-backups"
      accessKeyIDSecretRef:
        name: minio-credentials
        key: username
      secretAccessKeySecretRef:
        name: minio-credentials
        key: password
  restoreMethod:
    folder:
      claimName: "my-app-data"
  podSecurityContext:
    runAsUser: 1000
    fsGroup: 1000
EOF

# Wait for restore to complete
kubectl wait --for=condition=Completed restore/my-app-restore -n default --timeout=30m

# Scale up application
kubectl scale deployment my-app --replicas=1 -n default
```

### Restore Specific Snapshot

```bash
# Get snapshot ID from restic snapshots command
# Then restore:
kubectl apply -f - <<EOF
apiVersion: k8up.io/v1
kind: Restore
metadata:
  name: my-app-restore-specific
  namespace: default
spec:
  snapshot: "abcd1234567890"  # Snapshot ID
  backend:
    repoPasswordSecretRef:
      name: backup-repo
      key: password
    s3:
      endpoint: "http://minio.minio.svc.cluster.local:9000"
      bucket: "my-app-backups"
      accessKeyIDSecretRef:
        name: minio-credentials
        key: username
      secretAccessKeySecretRef:
        name: minio-credentials
        key: password
  restoreMethod:
    folder:
      claimName: "my-app-data"
  podSecurityContext:
    runAsUser: 1000
    fsGroup: 1000
EOF
```

### PostgreSQL Restore Procedure

```bash
# 1. Restore SQL dump to temporary PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-restore-temp
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: longhorn
EOF

# 2. Trigger restore
kubectl apply -f - <<EOF
apiVersion: k8up.io/v1
kind: Restore
metadata:
  name: postgres-restore
  namespace: default
spec:
  backend:
    repoPasswordSecretRef:
      name: backup-repo
      key: password
    s3:
      endpoint: "http://minio.minio.svc.cluster.local:9000"
      bucket: "postgres-backups"
      accessKeyIDSecretRef:
        name: minio-credentials
        key: username
      secretAccessKeySecretRef:
        name: minio-credentials
        key: password
  restoreMethod:
    folder:
      claimName: "postgres-restore-temp"
  podSecurityContext:
    runAsUser: 999
EOF

# 3. Wait for restore
kubectl wait --for=condition=Completed restore/postgres-restore -n default --timeout=30m

# 4. Apply SQL dump to database
kubectl run restore-apply --rm -it --image=postgres:16 \
  --overrides='{"spec":{"volumes":[{"name":"restore","persistentVolumeClaim":{"claimName":"postgres-restore-temp"}}],"containers":[{"name":"restore-apply","image":"postgres:16","volumeMounts":[{"name":"restore","mountPath":"/restore"}],"command":["bash"]}]}}' \
  --restart=Never -- bash

# Inside the pod:
# Find SQL file: ls /restore
# Apply dump: psql -h postgres-svc -U postgres -d postgres -f /restore/backup-postgres.sql

# 5. Cleanup
kubectl delete pvc postgres-restore-temp -n default
```

## Retention and Pruning

k8up uses Restic's retention policy to prune old backups.

### Prune Old Backups

```bash
kubectl apply -f - <<EOF
apiVersion: k8up.io/v1
kind: Prune
metadata:
  name: prune-old-backups
  namespace: default
spec:
  retention:
    keepLast: 5        # Keep last 5 backups
    keepDaily: 14      # Keep 14 daily backups
    keepWeekly: 4      # Keep 4 weekly backups
    keepMonthly: 12    # Keep 12 monthly backups
    keepYearly: 2      # Keep 2 yearly backups
  backend:
    repoPasswordSecretRef:
      name: backup-repo
      key: password
    s3:
      endpoint: "http://minio.minio.svc.cluster.local:9000"
      bucket: "my-app-backups"
      accessKeyIDSecretRef:
        name: minio-credentials
        key: username
      secretAccessKeySecretRef:
        name: minio-credentials
        key: password
EOF
```

### Check Backup Integrity

```bash
kubectl apply -f - <<EOF
apiVersion: k8up.io/v1
kind: Check
metadata:
  name: check-backups
  namespace: default
spec:
  backend:
    repoPasswordSecretRef:
      name: backup-repo
      key: password
    s3:
      endpoint: "http://minio.minio.svc.cluster.local:9000"
      bucket: "my-app-backups"
      accessKeyIDSecretRef:
        name: minio-credentials
        key: username
      secretAccessKeySecretRef:
        name: minio-credentials
        key: password
EOF
```

## Monitoring Backups

### View Backup Status

```bash
# List all backups
kubectl get backup -A

# Check specific backup
kubectl describe backup my-app-backup -n default

# View backup events
kubectl get events -n default --field-selector involvedObject.name=my-app-backup
```

### Check Backup Logs

```bash
# Find backup job
kubectl get jobs -n default | grep backup

# View job logs
kubectl logs -n default job/backup-my-app-backup-0

# Follow logs in real-time
kubectl logs -n default -f job/backup-my-app-backup-0
```

### Prometheus Metrics

k8up exposes Prometheus metrics for monitoring:

- `k8up_backup_start_time`: Backup start timestamp
- `k8up_backup_completion_time`: Backup completion timestamp
- `k8up_backup_failed`: Backup failure status

## Troubleshooting

### Backup Fails with Permission Denied

**Problem:** Backup pod cannot read PVC data

**Solution:** Set correct `runAsUser` and `fsGroup`:

```bash
# Check PVC file ownership
kubectl exec my-app-pod -n default -- ls -ln /data

# Use that UID in backup
spec:
  podSecurityContext:
    runAsUser: 1000  # Match PVC owner
    fsGroup: 1000
```

### S3 Connection Timeout

**Problem:** Cannot connect to S3 endpoint

**Solution:**

```bash
# Test S3 connectivity
kubectl run s3-test --rm -it --image=amazon/aws-cli --restart=Never -- \
  s3 ls s3://my-bucket --endpoint-url=http://minio.minio.svc.cluster.local:9000

# Check S3 credentials
kubectl get secret minio-credentials -n default -o yaml

# Verify endpoint URL format:
# - MinIO: http://minio.minio.svc.cluster.local:9000
# - AWS S3: https://s3.amazonaws.com
# - Wasabi: https://s3.us-west-1.wasabisys.com
```

### Backup Stuck in Running State

**Problem:** Backup never completes

**Solution:**

```bash
# Check backup job logs
kubectl logs -n default -l job-name=backup-my-app-backup-0

# Check backup pod status
kubectl get pods -n default | grep backup-my-app

# Delete stuck backup
kubectl delete backup my-app-backup -n default --force --grace-period=0

# Check for PVC mount issues
kubectl describe pod backup-my-app-backup-0-xxx -n default
```

### Restore Fails with "snapshot not found"

**Problem:** Cannot find snapshot to restore

**Solution:**

```bash
# List available snapshots
kubectl run restic-check --rm -it --image=restic/restic --restart=Never -- \
  -r s3:http://minio.minio.svc.cluster.local:9000/my-app-backups snapshots

# Check S3 bucket contents
kubectl run aws-cli --rm -it --image=amazon/aws-cli --restart=Never -- \
  s3 ls s3://my-app-backups --recursive --endpoint-url=http://minio.minio.svc.cluster.local:9000

# Verify Restic password
kubectl get secret backup-repo -n default -o jsonpath='{.data.password}' | base64 -d
```

### Database Backup Has No Data

**Problem:** SQL dump is empty or missing

**Solution:**

```bash
# Test backup command manually
kubectl exec postgres-0 -n default -- \
  sh -c 'PGDATABASE=$POSTGRES_DB PGUSER=$POSTGRES_USER PGPASSWORD=$POSTGRES_PASSWORD pg_dump --clean'

# Check pod annotations
kubectl get pod postgres-0 -n default -o yaml | grep -A5 annotations

# Verify environment variables exist
kubectl exec postgres-0 -n default -- env | grep POSTGRES
```

### Restic Repository Lock Error

**Problem:** "repository is already locked"

**Solution:**

```bash
# Unlock repository (only if no backup is running!)
kubectl run restic-unlock --rm -it --image=restic/restic --restart=Never -- \
  -r s3:http://minio.minio.svc.cluster.local:9000/my-app-backups unlock

# Check for stale backup jobs
kubectl get jobs -n default | grep backup
kubectl delete job backup-my-app-backup-0 -n default
```

## Migration from k3s-ansible

If you're migrating from the k3s-ansible `k8up` role:

### Key Differences

| k3s-ansible | k8s-homelab |
|-------------|-------------|
| Ansible role manages operator + backups | Manual Helm install for operator |
| Backup/restore via Ansible playbooks | Manual CRD application |
| Variables in `defaults/main.yml` | Secrets in `secrets.yaml` |
| Chart version: 4.8.3 | Same version, update as needed |

### Migration Steps

1. **Install k8up operator** (if not already present):
   ```bash
   kubectl apply -f https://github.com/k8up-io/k8up/releases/download/k8up-4.8.3/k8up-crd.yaml
   helm upgrade --install k8up k8up-io/k8up \
     --namespace k8up-system \
     --create-namespace \
     -f custom-values.yaml \
     --version 4.8.3
   ```

2. **Verify existing secrets**:
   ```bash
   kubectl get secret minio-credentials backup-repo -n default
   ```

3. **Existing backups remain accessible**: Restic repositories in S3 are independent of k8up installation

4. **Convert Ansible backup lists to Schedule CRDs**: Replace `k8up_backup_list` with Schedule manifests

5. **No data migration needed**: Backup data in S3 persists regardless of operator installation method

### Ansible Variables Mapping

```yaml
# k3s-ansible (defaults/main.yml)
k8up_chart_version: "4.8.3"
k8up_chart_namespace: "k8up-system"
minio_endpoint: "http://minio.com:9000"
minio_bucket: "backup"
minio_access_key: "access-key"
minio_secret_key: "secret-key"
minio_repository_password: "restic-password"

# k8s-homelab (secrets.yaml)
apiVersion: v1
kind: Secret
metadata:
  name: minio-credentials
stringData:
  username: "access-key"
  password: "secret-key"
---
apiVersion: v1
kind: Secret
metadata:
  name: backup-repo
stringData:
  password: "restic-password"
```

### Backup List Conversion

k3s-ansible used `k8up_backup_list` to define backups:

```yaml
# k3s-ansible
k8up_backup_list:
  - name: "nextcloud"
    pvc_name: "nfs-nextcloud"
    deployment_name: "nextcloud"
    run_as_user: 33
```

Convert to k8s-homelab Schedule:

```yaml
# k8s-homelab
apiVersion: k8up.io/v1
kind: Schedule
metadata:
  name: nextcloud-backup
  namespace: default
spec:
  backup:
    schedule: "0 2 * * *"
    backend:
      # ... S3 config
    podSecurityContext:
      runAsUser: 33
```

## Additional Resources

- **Official Documentation**: https://k8up.io/
- **GitHub Repository**: https://github.com/k8up-io/k8up
- **Helm Chart**: https://github.com/k8up-io/k8up/tree/master/charts/k8up
- **Restic Documentation**: https://restic.readthedocs.io/
- **S3 Providers**: AWS S3, MinIO, Wasabi, Backblaze B2, DigitalOcean Spaces

## Support

For issues or questions:
- k8up GitHub Issues: https://github.com/k8up-io/k8up/issues
- k8up Discussions: https://github.com/k8up-io/k8up/discussions
- Restic Forum: https://forum.restic.net/
