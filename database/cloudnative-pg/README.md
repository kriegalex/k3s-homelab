# CloudNativePG Installation Guide

CloudNativePG is a Kubernetes operator for managing PostgreSQL databases natively in Kubernetes. It provides high availability, automated failover, backup/restore, and complete PostgreSQL lifecycle management.

## Table of Contents

- [Prerequisites](#prerequisites)
- [What is CloudNativePG?](#what-is-cloudnativepg)
- [When to Use CloudNativePG](#when-to-use-cloudnativepg)
- [Installation](#installation)
- [Creating a PostgreSQL Cluster](#creating-a-postgresql-cluster)
- [Connecting to Your Database](#connecting-to-your-database)
- [Backup and Restore](#backup-and-restore)
- [High Availability](#high-availability)
- [Upgrading](#upgrading)
- [Troubleshooting](#troubleshooting)
- [Migration from k3s-ansible](#migration-from-k3s-ansible)

## Prerequisites

- Kubernetes cluster v1.25+ with kubectl configured
- Helm 3.0+
- Storage provisioner (e.g., longhorn, local-path, nfs-client)
- Minimum 2GB RAM per PostgreSQL instance
- For backups: S3-compatible storage (AWS S3, MinIO, Wasabi, etc.)

## What is CloudNativePG?

CloudNativePG is a **Kubernetes operator** that manages PostgreSQL databases. Unlike traditional Helm charts that deploy a single PostgreSQL instance, CloudNativePG:

- Manages the complete PostgreSQL lifecycle (provisioning, updates, failover)
- Provides native Kubernetes integration (CRDs, operators, service discovery)
- Handles high availability automatically (primary/standby architecture)
- Automates backup/restore operations
- Supports PostgreSQL 13, 14, 15, 16, 17

### Comparison with Bitnami PostgreSQL

| Feature | CloudNativePG | Bitnami PostgreSQL |
|---------|---------------|-------------------|
| Deployment Type | Operator (CRDs) | Helm Chart |
| Complexity | Higher | Lower |
| HA Configuration | Automatic | Manual setup required |
| Backup/Restore | Built-in with Barman | Requires external tools |
| Kubernetes Native | Yes | No (basic StatefulSet) |
| Resource Usage | Higher (operator + instances) | Lower |
| Learning Curve | Steeper | Gentler |
| Best For | Production HA clusters | Simple deployments |

## When to Use CloudNativePG

### Use CloudNativePG when:

- Your applications run inside the same Kubernetes cluster
- You need automated high availability for production workloads
- You want native Kubernetes integration (operators, CRDs)
- You need automated backup/restore capabilities
- You're comfortable managing Kubernetes resources
- You need multiple PostgreSQL clusters with centralized management

### Skip CloudNativePG when:

- You need a simple single-instance database
- Your applications run outside Kubernetes
- You're new to Kubernetes and want to start simple
- You prefer traditional database management
- You have limited cluster resources (< 4GB RAM)

## Installation

### Step 1: Add Helm Repository

```bash
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update
```

### Step 2: Install the Operator

The operator is installed once per cluster and can manage multiple PostgreSQL databases.

```bash
# Create namespace
kubectl create namespace cnpg-system

# Install operator
helm upgrade --install cnpg cnpg/cloudnative-pg \
  --namespace cnpg-system \
  --create-namespace \
  -f values.yaml \
  --version 0.23.2
```

### Step 3: Verify Installation

```bash
# Check operator pod
kubectl get pods -n cnpg-system

# Check CRDs
kubectl get crd | grep postgresql.cnpg.io

# Expected CRDs:
# - backups.postgresql.cnpg.io
# - clusters.postgresql.cnpg.io
# - poolers.postgresql.cnpg.io
# - scheduledbackups.postgresql.cnpg.io
```

## Creating a PostgreSQL Cluster

After installing the operator, you create PostgreSQL clusters using the `Cluster` CRD.

### Step 1: Create Database Credentials Secret

```bash
# Generate secure password
DB_PASSWORD=$(openssl rand -base64 32)

# Create secret
kubectl create secret generic myapp-db-credentials \
  --from-literal=username=myapp_user \
  --from-literal=password="$DB_PASSWORD" \
  --namespace=default

# Save password for later
echo "Database password: $DB_PASSWORD"
```

### Step 2: Create Cluster Manifest

Copy `example-cluster.yaml` and customize:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: myapp-cluster
  namespace: default
spec:
  instances: 3  # 1 primary + 2 replicas

  bootstrap:
    initdb:
      database: myapp_db
      owner: myapp_user
      secret:
        name: myapp-db-credentials

  storage:
    size: 10Gi
    storageClass: longhorn

  resources:
    requests:
      memory: "500Mi"
      cpu: "250m"
    limits:
      memory: "2Gi"
      cpu: "1000m"
```

### Step 3: Apply the Cluster

```bash
# Apply manifest
kubectl apply -f myapp-cluster.yaml

# Watch cluster creation
kubectl get cluster -w -n default

# Check pod status
kubectl get pods -l postgresql=myapp-cluster -n default
```

The operator will create:
- `myapp-cluster-1` (primary)
- `myapp-cluster-2` (replica)
- `myapp-cluster-3` (replica)

## Connecting to Your Database

CloudNativePG automatically creates Kubernetes services for your cluster.

### Service Endpoints

```bash
# List services
kubectl get svc -l postgresql=myapp-cluster -n default
```

**Services created:**

1. **`myapp-cluster-rw`** (Read-Write): Primary instance only
   - Use for: INSERT, UPDATE, DELETE operations
   - Connection: `myapp-cluster-rw.default.svc.cluster.local:5432`

2. **`myapp-cluster-ro`** (Read-Only): All replicas (load balanced)
   - Use for: SELECT queries
   - Connection: `myapp-cluster-ro.default.svc.cluster.local:5432`

3. **`myapp-cluster-r`** (Read): All instances including primary
   - Use for: Read queries when you want to distribute load
   - Connection: `myapp-cluster-r.default.svc.cluster.local:5432`

### Connection Examples

#### From Pod in Same Namespace

```bash
# Connect to primary (read-write)
psql "postgresql://myapp_user:password@myapp-cluster-rw:5432/myapp_db"

# Connect to replica (read-only)
psql "postgresql://myapp_user:password@myapp-cluster-ro:5432/myapp_db"
```

#### Application Configuration

```yaml
# Example: Nextcloud Helm values
postgresql:
  enabled: false

externalDatabase:
  host: myapp-cluster-rw.default.svc.cluster.local
  port: 5432
  database: myapp_db
  existingSecret:
    secretName: myapp-db-credentials
    usernameKey: username
    passwordKey: password
```

#### Get Connection Details

```bash
# Get database credentials
kubectl get secret myapp-db-credentials -n default \
  -o jsonpath='{.data.username}' | base64 -d; echo
kubectl get secret myapp-db-credentials -n default \
  -o jsonpath='{.data.password}' | base64 -d; echo

# Get cluster status
kubectl get cluster myapp-cluster -n default -o yaml
```

## Backup and Restore

CloudNativePG uses Barman for backup management with S3-compatible storage.

### Step 1: Configure S3 Credentials

See `example-backup-config.yaml` for complete configuration.

```bash
# Create S3 credentials secret
kubectl create secret generic backup-s3-credentials \
  --from-literal=ACCESS_KEY_ID="your-access-key" \
  --from-literal=SECRET_ACCESS_KEY="your-secret-key" \
  --namespace=default
```

### Step 2: Enable Backups in Cluster

Add backup configuration to your Cluster manifest:

```yaml
spec:
  backup:
    barmanObjectStore:
      destinationPath: s3://my-bucket/postgres-backups
      endpointURL: https://s3.amazonaws.com
      s3Credentials:
        accessKeyId:
          name: backup-s3-credentials
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: backup-s3-credentials
          key: SECRET_ACCESS_KEY
      wal:
        compression: gzip
    retentionPolicy: "30d"
```

### Step 3: Schedule Automated Backups

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: myapp-cluster-daily-backup
  namespace: default
spec:
  schedule: "30 2 * * *"  # Daily at 2:30 AM
  cluster:
    name: myapp-cluster
  method: barmanObjectStore
```

### Manual Backup

```bash
# Trigger immediate backup
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: myapp-cluster-backup-$(date +%Y%m%d-%H%M%S)
  namespace: default
spec:
  cluster:
    name: myapp-cluster
  method: barmanObjectStore
EOF

# Check backup status
kubectl get backup -n default
```

### Restore from Backup

See `example-backup-config.yaml` for complete restore example.

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: myapp-cluster-restored
  namespace: default
spec:
  instances: 3

  bootstrap:
    recovery:
      source: myapp-cluster

  externalClusters:
    - name: myapp-cluster
      barmanObjectStore:
        destinationPath: s3://my-bucket/postgres-backups
        endpointURL: https://s3.amazonaws.com
        s3Credentials:
          accessKeyId:
            name: backup-s3-credentials
            key: ACCESS_KEY_ID
          secretAccessKey:
            name: backup-s3-credentials
            key: SECRET_ACCESS_KEY
```

## High Availability

CloudNativePG provides automatic failover and high availability.

### How HA Works

1. **Primary Election**: One instance is elected as primary (read-write)
2. **Replication**: Replicas continuously sync from primary
3. **Failover**: If primary fails, a replica is promoted automatically
4. **Service Update**: Services are updated to point to new primary

### Check Cluster Status

```bash
# View cluster status
kubectl get cluster myapp-cluster -n default

# Expected output shows:
# - Primary instance
# - Number of replicas
# - Cluster health

# Detailed status
kubectl describe cluster myapp-cluster -n default
```

### Simulate Failover

```bash
# Delete primary pod (operator will promote a replica)
kubectl delete pod myapp-cluster-1 -n default

# Watch failover
kubectl get cluster myapp-cluster -n default -w

# Check new primary
kubectl get cluster myapp-cluster -n default -o jsonpath='{.status.currentPrimary}'
```

### Scaling

```bash
# Scale to 5 instances
kubectl patch cluster myapp-cluster -n default \
  --type='json' -p='[{"op": "replace", "path": "/spec/instances", "value": 5}]'

# Scale down to 1 instance
kubectl patch cluster myapp-cluster -n default \
  --type='json' -p='[{"op": "replace", "path": "/spec/instances", "value": 1}]'
```

## Upgrading

### Upgrade Operator

```bash
# Update Helm repo
helm repo update

# Upgrade operator
helm upgrade cnpg cnpg/cloudnative-pg \
  --namespace cnpg-system \
  -f values.yaml \
  --version 0.24.0  # New version
```

### Upgrade PostgreSQL Version

CloudNativePG supports in-place PostgreSQL upgrades.

```bash
# Update cluster manifest with new image
kubectl patch cluster myapp-cluster -n default \
  --type='json' -p='[{
    "op": "replace",
    "path": "/spec/imageName",
    "value": "ghcr.io/cloudnative-pg/postgresql:16"
  }]'

# Operator will perform rolling upgrade
kubectl get cluster myapp-cluster -n default -w
```

## Troubleshooting

### Cluster Won't Start

```bash
# Check operator logs
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg

# Check cluster events
kubectl describe cluster myapp-cluster -n default

# Check pod logs
kubectl logs myapp-cluster-1 -n default

# Common issues:
# - Missing storage class
# - Insufficient resources
# - Missing credentials secret
# - PVC provisioning failure
```

### Connection Issues

```bash
# Check services
kubectl get svc -l postgresql=myapp-cluster -n default

# Test connectivity from debug pod
kubectl run debug-pod --rm -it --image=postgres:16 --restart=Never -- \
  psql "postgresql://myapp_user:password@myapp-cluster-rw:5432/myapp_db"

# Verify credentials
kubectl get secret myapp-db-credentials -n default -o yaml

# Check PostgreSQL logs
kubectl logs myapp-cluster-1 -n default
```

### Backup Failures

```bash
# Check backup status
kubectl get backup -n default
kubectl describe backup myapp-cluster-backup-20240208 -n default

# Check S3 credentials
kubectl get secret backup-s3-credentials -n default -o yaml

# Test S3 connectivity
kubectl run s3-test --rm -it --image=amazon/aws-cli --restart=Never -- \
  s3 ls s3://my-bucket/postgres-backups \
  --endpoint-url=https://s3.amazonaws.com

# Check operator logs for backup errors
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg | grep -i backup
```

### Backups fail with `InvalidDigest` on QNAP QuObjects (newer PostgreSQL images)

**Symptom**

```
ERROR: ... (InvalidDigest) when calling the PutObject operation:
The Content-MD5 or checksum value that you specified is not valid.
```

- WAL archiving is stuck: the cluster shows `ContinuousArchiving = False` (`ContinuousArchivingFailing`) and backups never complete (`walArchivingFailing`, or a base backup that hangs in `running`).
- On the QNAP, the bucket folder `/share/cnpg-backup/<bucket>/` contains only `.s3_multipart_uploads/` (orphaned, never-finished uploads) — no committed `<cluster>/base/` + `<cluster>/wals/`.

> Note: `kubectl get backup` resolves to **Longhorn's** CRD, not CNPG's. Use the full name: `kubectl get backup.postgresql.cnpg.io -n <ns>`.

**Cause** — a client/server checksum mismatch tied to the **PostgreSQL image version**:

- The CNPG instance image bundles the AWS SDK (`botocore`). **botocore ≥ 1.36** (shipped in newer `postgresql:17.x` images) attaches an `x-amz-checksum-crc32` integrity checksum to every `PutObject`/`UploadPart` by default.
- Our backup target is the QNAP **"QuObjects"** S3 endpoint (`http://10.0.0.7:8010`) — OpenStack Swift behind the legacy **`swift3`** gateway, which **rejects** that checksum → `InvalidDigest`.
- Older images (botocore < 1.36) never send the checksum, so they keep working. That's why only *some* clusters break.

| PostgreSQL image | botocore | Backups to QuObjects |
|------------------|----------|----------------------|
| 16.x             | 1.35.x   | ✅ works             |
| 17.2             | < 1.36   | ✅ works             |
| 17.5             | 1.40.x   | ❌ `InvalidDigest`   |

> ⚠️ **Time bomb:** any cluster upgraded to a botocore-≥1.36 image will start failing the same way. Apply the fix below at the same time you bump the image.

**Fix** — tell the SDK not to send the new checksum, via two env vars on the `Cluster` spec:

```yaml
spec:
  env:
    - name: AWS_REQUEST_CHECKSUM_CALCULATION
      value: when_required
    - name: AWS_RESPONSE_CHECKSUM_VALIDATION
      value: when_required
```

Applying this triggers a rolling restart of the cluster (replicas first, then a primary switchover — a few seconds of write interruption). After it settles, `ContinuousArchiving` returns to `True` and backups complete. Applied here on `n8n-db` and `event-manager-postgres` (2026-06).

**Verify**

```bash
# Archiving healthy again?
kubectl get cluster <name> -n <ns> \
  -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].status}{"\n"}'

# Committed objects on the QNAP — should show base/ + wals/, not just .s3_multipart_uploads/
ssh -p 1022 admin@10.0.0.7 'ls /share/cnpg-backup/<bucket>/<cluster>/'
```

### Performance Issues

```bash
# Check resource usage
kubectl top pod -l postgresql=myapp-cluster -n default

# Check storage performance
kubectl describe pvc -n default

# Tune PostgreSQL parameters in cluster spec
# spec:
#   postgresql:
#     parameters:
#       max_connections: "200"
#       shared_buffers: "512MB"
#       effective_cache_size: "2GB"
```

### View Cluster Status

```bash
# Quick status
kubectl get cluster myapp-cluster -n default

# Detailed status
kubectl get cluster myapp-cluster -n default -o yaml

# Check all instances
kubectl get pods -l postgresql=myapp-cluster -n default

# Check replication status
kubectl exec myapp-cluster-1 -n default -- \
  psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

## Migration from k3s-ansible

If you're migrating from the k3s-ansible `cloudnative_pg` role:

### Key Differences

| k3s-ansible | k8s-homelab |
|-------------|-------------|
| Ansible role deploys operator | Manual Helm install |
| Variables in `defaults/main.yaml` | Helm values in `values.yaml` |
| Clusters created via Ansible templates | Manual Cluster CRD application |
| Chart version: 0.23.0 | Live version: 0.23.2 |

### Migration Steps

1. **Install operator** (if not already present):
   ```bash
   helm upgrade --install cnpg cnpg/cloudnative-pg \
     --namespace cnpg-system \
     --create-namespace \
     -f values.yaml \
     --version 0.23.2
   ```

2. **Existing clusters remain unchanged**: CloudNativePG clusters are CRDs managed by the operator, not by Helm. Your existing PostgreSQL clusters will continue running.

3. **Update cluster configurations**: If you need to modify existing clusters, use `kubectl edit cluster <name>` or apply updated manifests.

4. **Backup configuration**: If you configured backups via Ansible, verify S3 credentials are still present:
   ```bash
   kubectl get secret backup-s3-credentials -n default
   ```

5. **No data migration needed**: PostgreSQL data persists in PVCs and is not affected by operator installation method.

### Ansible Variables Mapping

```yaml
# k3s-ansible (defaults/main.yaml)
cloudnative_pg_enabled: true
cloudnative_pg_chart_version: 0.23.0
cloudnative_pg_release_name: cnpg
cloudnative_pg_namespace: cnpg-system

# k8s-homelab (helm command)
helm upgrade --install cnpg cnpg/cloudnative-pg \
  --namespace cnpg-system \
  --version 0.23.2
```

## Additional Resources

- **Official Documentation**: https://cloudnative-pg.io/documentation/
- **Helm Chart**: https://github.com/cloudnative-pg/charts
- **GitHub Repository**: https://github.com/cloudnative-pg/cloudnative-pg
- **Backup with Barman**: https://www.pgbarman.org/
- **PostgreSQL Documentation**: https://www.postgresql.org/docs/

## Support

For issues or questions:
- CloudNativePG GitHub Issues: https://github.com/cloudnative-pg/cloudnative-pg/issues
- Kubernetes Slack #cloudnativepg channel
- PostgreSQL Community: https://www.postgresql.org/support/
