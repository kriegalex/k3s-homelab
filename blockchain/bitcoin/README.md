# Bitcoin Stack

Complete Bitcoin infrastructure deployment on Kubernetes using Helm.

## Overview

This deploys a full Bitcoin stack including:
- **Bitcoin Core**: Full node that validates and relays transactions and blocks
- **Electrs** (optional): Electrum Rust Server for wallet support and blockchain indexing
- **Mempool** (optional): Blockchain explorer with frontend, backend, and database

This is useful for:
- Running your own Bitcoin node for privacy and security
- Building applications that interact with the Bitcoin network
- Operating an Electrum server for wallet support
- Hosting a mempool explorer for transaction visualization
- Supporting the Bitcoin network decentralization

> **⚠️ WARNING:** This Helm chart deployment has been minimally tested and never used in production. Use at your own risk and thoroughly test in a non-production environment before deploying to production. Always verify the configuration and ensure you have proper backups.

## Prerequisites

- Kubernetes cluster with storage provisioner
- **Storage requirements:**
  - Bitcoin Core: **500GB+** (full node) or **50GB** (pruned mode)
  - Electrs: **1200GB+** (if enabled)
  - Mempool DB: **10GB** (if enabled)
- Helm 3.x installed
- **Optional:** LoadBalancer for P2P connectivity (recommended for full participation)
- **Optional:** Ingress controller for web access (cert-manager for HTTPS)

## Architecture

```
┌────────────────────────────────────────────────┐
│         Bitcoin Stack Deployment              │
│                                                │
│  ┌──────────────┐      ┌─────────────────┐   │
│  │ Bitcoin Core │◄─────┤    Electrs      │   │
│  │   (bitcoind) │      │ (Electrum Srv)  │   │
│  │              │      │                 │   │
│  │ Port: 8332   │      │ RPC: 50001     │   │
│  │ Port: 8333   │      │ HTTP: 3000     │   │
│  └──────────────┘      └─────────────────┘   │
│         │                      │              │
│         │                      │              │
│         └──────────┬───────────┘              │
│                    │                          │
│           ┌────────▼────────┐                 │
│           │   Mempool       │                 │
│           │   Explorer      │                 │
│           │                 │                 │
│           │ Frontend (nginx)│                 │
│           │ Backend (node)  │                 │
│           │ Database (maria)│                 │
│           └─────────────────┘                 │
│                                                │
└────────────────────────────────────────────────┘
          │              │              │
          ▼              ▼              ▼
    ┌─────────┐   ┌──────────┐   ┌──────────┐
    │Bitcoin  │   │ Electrs  │   │ Mempool  │
    │PVC      │   │ PVC      │   │ DB PVC   │
    │(500GB+) │   │(1200GB+) │   │ (10GB)   │
    └─────────┘   └──────────┘   └──────────┘
```

## Installation

### 1. Create Namespace

```bash
kubectl create namespace bitcoin
```

### 2. Add Helm Repository

This deployment uses a custom Helm chart:

```bash
helm repo add k8s-charts https://kriegalex.github.io/k8s-charts/
helm repo update
```

> **Note:** This chart is part of a custom charts repository. Ensure the repository is available and maintained.

### 3. Configure Storage

The stack requires storage for multiple components:

#### Bitcoin Core Storage (Required)

**Option A: NFS Storage (Recommended)**

```yaml
# bitcoin-nfs-pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: bitcoin-nfs-pv
spec:
  capacity:
    storage: 500Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  nfs:
    server: 10.0.0.2  # Your NFS server
    path: /mnt/user/bitcoin
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: bitcoin-nfs-pvc
  namespace: bitcoin
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 500Gi
  volumeName: bitcoin-nfs-pv
```

```bash
kubectl apply -f bitcoin-nfs-pv.yaml
```

**Option B: Dynamic Provisioning**

Let the chart create a PVC using your storage class (see values.yaml).

#### Electrs Storage (Optional, if enabled)

If enabling Electrs, create another PV/PVC:

```yaml
# electrs-nfs-pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: electrs-nfs-pv
spec:
  capacity:
    storage: 1200Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  nfs:
    server: 10.0.0.7  # Your NFS server
    path: /electrs
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: electrs-nfs-pvc
  namespace: bitcoin
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 1200Gi
  volumeName: electrs-nfs-pv
```

```bash
kubectl apply -f electrs-nfs-pv.yaml
```

### 4. Customize Helm Values

Create `custom-values.yaml`:

```yaml
# Basic Bitcoin Core configuration
image:
  repository: blockstream/bitcoind
  tag: ""  # Uses chart default
  pullPolicy: IfNotPresent

bitcoind:
  testnet: 0  # Set to 1 for testnet
  regtest: 0  # Set to 1 for regtest

  config: |
    server=1
    txindex=1
    chain=main

    # RPC configuration
    rpcuser=bitcoinrpc
    rpcpassword=CHANGE_ME  # Generate with: openssl rand -base64 24
    rpcallowip=10.0.0.0/8
    whitelist=10.0.0.0/8
    rpcbind=0.0.0.0

    # Performance
    dbcache=450
    maxorphantx=100
    maxmempool=300

    # Optional: Enable pruning
    # prune=10240

  persistence:
    enabled: true
    existingClaim: "bitcoin-nfs-pvc"  # Or use storageClass
    # storageClass: "longhorn"
    # size: 500Gi

# Resources
resources:
  requests:
    memory: 2Gi
    cpu: 500m
  limits:
    memory: 8Gi
    cpu: 2000m

# Service
service:
  type: ClusterIP  # Or LoadBalancer for P2P

# Ingress for RPC access (optional)
ingress:
  enabled: false
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: bitcoin.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: bitcoin-tls-secret
      hosts:
        - bitcoin.example.com

# Electrs (optional)
electrs:
  enabled: false  # Set to true to enable
  persistence:
    enabled: true
    existingClaim: "electrs-nfs-pvc"
    # storageClass: "longhorn"
    # size: 1200Gi

# Mempool Explorer (optional)
mempool:
  enabled: false  # Set to true to enable
  db:
    auth:
      password: "changeme"  # Change this!
      rootPassword: "changeme"  # Change this!
  ingress:
    enabled: false
    hosts:
      - host: mempool.example.com
        paths:
          - path: /
            pathType: Prefix
```

### 5. Install with Helm

```bash
helm upgrade --install bitcoin-stack k8s-charts/bitcoin-stack \
  --namespace bitcoin \
  --create-namespace \
  --version 1.0.0 \
  -f custom-values.yaml
```

### 6. Verify Deployment

```bash
# Check pod status
kubectl get pods -n bitcoin

# Check services
kubectl get svc -n bitcoin

# Check PVCs
kubectl get pvc -n bitcoin

# View Bitcoin Core logs
kubectl logs -n bitcoin -l app.kubernetes.io/name=bitcoin-stack -c bitcoind -f

# Check sync status (once pod is running)
POD=$(kubectl get pod -n bitcoin -l app.kubernetes.io/name=bitcoin-stack -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n bitcoin $POD -c bitcoind -- bitcoin-cli getblockchaininfo
```

## Configuration Options

### Bitcoin Networks

Set in `bitcoind.testnet` or `bitcoind.regtest`:
- **Mainnet** (default): `testnet: 0`, `regtest: 0`
- **Testnet**: `testnet: 1`, `regtest: 0`
- **Regtest**: `testnet: 0`, `regtest: 1`

### Pruning Mode

Reduce storage to ~50GB:

```yaml
bitcoind:
  config: |
    prune=10240  # Keep only 10GB of blocks
```

**Note:** Pruned nodes cannot serve full blockchain history to other nodes or Electrs.

### Enabling Electrs

Electrs provides an Electrum server interface for wallets:

```yaml
electrs:
  enabled: true
  image:
    repository: mempool/electrs
    tag: latest
  resources:
    requests:
      memory: 4Gi
      cpu: 500m
    limits:
      memory: 8Gi
      cpu: 2000m
  persistence:
    enabled: true
    existingClaim: "electrs-nfs-pvc"
  service:
    type: ClusterIP
    rpcPort: 50001
    httpPort: 3000
```

**Storage:** Electrs requires ~1.2TB for mainnet full index.

### Enabling Mempool Explorer

Mempool provides a web interface for blockchain exploration:

```yaml
mempool:
  enabled: true
  backend:
    config:
      backend: "esplora"  # or "electrum"
      network: "mainnet"
  db:
    auth:
      password: "secure-password"
      rootPassword: "secure-root-password"
    persistence:
      enabled: true
      size: 10Gi
      storageClass: "longhorn"
  ingress:
    enabled: true
    className: "nginx"
    annotations:
      cert-manager.io/cluster-issuer: "letsencrypt-prod"
    hosts:
      - host: mempool.example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: mempool-tls-secret
        hosts:
          - mempool.example.com
```

> **⚠️ Security Note:** The chart does not yet support Kubernetes secrets for database credentials. Passwords must be set directly in values.yaml. Use strong passwords (`openssl rand -base64 32`) and consider encrypting your values file with `helm secrets`, SOPS, or using external secrets management.

## Storage Requirements

| Component | Storage | Sync Time | Notes |
|-----------|---------|-----------|-------|
| Bitcoin Core (Full) | 500GB+ | 3-7 days | Full validation |
| Bitcoin Core (Pruned) | 50GB | 3-7 days | Validation only |
| Electrs | 1200GB+ | 1-3 days* | Requires full node |
| Mempool DB | 10GB | N/A | Transaction database |

\* After Bitcoin Core is fully synced

## Performance Tuning

### Faster Bitcoin Sync

```yaml
bitcoind:
  config: |
    dbcache=4096  # Requires more RAM
    maxconnections=125

resources:
  limits:
    memory: 16Gi  # Increase for larger dbcache
```

### LoadBalancer for P2P

Better connectivity for inbound Bitcoin connections:

```yaml
service:
  type: LoadBalancer
```

## Accessing Services

### Bitcoin RPC

From within the cluster:
```bash
kubectl exec -n bitcoin <pod-name> -c bitcoind -- \
  bitcoin-cli -rpcuser=bitcoinrpc -rpcpassword=<password> getblockchaininfo
```

Via ingress (if enabled):
```bash
curl -u bitcoinrpc:<password> https://bitcoin.example.com/
```

### Electrs API

```bash
# Via port-forward
kubectl port-forward -n bitcoin svc/bitcoin-stack-electrs 3000:3000

# Access at http://localhost:3000/
```

### Mempool Explorer

Access via ingress at `https://mempool.example.com` (if enabled).

## Monitoring

### Check Bitcoin Sync Progress

```bash
POD=$(kubectl get pod -n bitcoin -l app.kubernetes.io/name=bitcoin-stack -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n bitcoin $POD -c bitcoind -- bitcoin-cli getblockchaininfo | jq '{blocks, headers, verificationprogress}'
```

### Check Electrs Sync

```bash
kubectl logs -n bitcoin -l app.kubernetes.io/component=electrs -f
```

Look for: "Electrs is ready"

### Resource Usage

```bash
kubectl top pod -n bitcoin
```

## Backup and Recovery

### Backup Blockchain Data

1. **Stop the pod** (optional but recommended):
   ```bash
   kubectl scale statefulset -n bitcoin bitcoin-stack --replicas=0
   ```

2. **Backup PVCs** using your backup solution (k8up, velero, etc.)

3. **Restart the pod**:
   ```bash
   kubectl scale statefulset -n bitcoin bitcoin-stack --replicas=1
   ```

### Restore from Backup

1. Restore PVC data from backup
2. Deploy with Helm pointing to restored PVCs
3. Verify data integrity:
   ```bash
   kubectl exec -n bitcoin <pod> -c bitcoind -- bitcoin-cli verifychain
   ```

## Troubleshooting

### Pod Not Starting

```bash
kubectl describe pod -n bitcoin <pod-name>
kubectl logs -n bitcoin <pod-name> -c bitcoind
```

Common issues:
- **PVC binding failure**: Check storage class and capacity
- **OOM killed**: Increase memory limits or reduce `dbcache`
- **Init errors**: Check bitcoin.conf syntax in values

### Slow Sync

- Increase `dbcache` (requires more RAM)
- Use LoadBalancer for better P2P connectivity
- Check disk I/O performance
- Verify network connectivity

### Electrs Not Syncing

- Ensure Bitcoin Core is fully synced first
- Check logs: `kubectl logs -n bitcoin <pod> -c electrs`
- Verify RPC connectivity to bitcoind
- Ensure sufficient storage (1.2TB+)

### Mempool Not Loading

- Check all containers are running: `kubectl get pods -n bitcoin`
- Verify database connectivity
- Check backend logs: `kubectl logs -n bitcoin <pod> -c mempool-backend`
- Ensure Electrs or Bitcoin RPC is accessible

## Upgrade

```bash
helm repo update

helm upgrade bitcoin-stack k8s-charts/bitcoin-stack \
  --namespace bitcoin \
  --version <new-version> \
  -f custom-values.yaml
```

**Note:** Always backup before upgrading.

## Uninstall

```bash
# Remove Helm release
helm uninstall bitcoin-stack -n bitcoin

# Remove namespace (WARNING: Deletes PVCs if not using external PVs)
kubectl delete namespace bitcoin

# If using NFS PVs with Retain policy:
kubectl delete pv bitcoin-nfs-pv electrs-nfs-pv
```

## Security Considerations

1. **RPC Credentials**: Use strong passwords, store in Kubernetes secrets
2. **Network Isolation**: Restrict RPC access with `rpcallowip`
3. **Resource Limits**: Set appropriate CPU/memory limits
4. **Ingress Authentication**: Use basic auth or OAuth for public endpoints
5. **Database Passwords**:
   - ⚠️ **Important**: The chart does not yet support `existingSecret` for Mempool database credentials
   - Passwords must be set directly in values.yaml (`mempool.db.auth.password`)
   - Use strong passwords: `openssl rand -base64 32`
   - Consider encrypting your values file with tools like `helm secrets` or SOPS
   - Alternatively, use external secrets management (External Secrets Operator, Sealed Secrets)
6. **Network Policies**: Enable and configure for production
7. **Pod Security**: Enable security contexts in production

## Component Versions

- **Bitcoin Core Image**: `blockstream/bitcoind` (tag specified in chart)
- **Electrs Image**: `mempool/electrs:latest`
- **Mempool Frontend**: `mempool/frontend:v2.5.1`
- **Mempool Backend**: `mempool/backend:v2.5.1`
- **MariaDB**: `mariadb:10.5.21`

## References

- [Bitcoin Core Documentation](https://bitcoin.org/en/bitcoin-core/)
- [Electrs GitHub](https://github.com/romanz/electrs)
- [Mempool Explorer](https://mempool.space/)
- [Custom Helm Chart](https://github.com/kriegalex/k8s-charts)

## Migration from k3s-ansible

This deployment is migrated from [k3s-ansible](https://github.com/kriegalex/k3s-ansible) (refactor-backup branch).

Key differences:
- **Manual Helm deployment** instead of Ansible automation
- **Custom chart** (`k8s-charts/bitcoin-stack`) instead of `hirosystems/bitcoin-core`
- **Full stack support**: Bitcoin Core + Electrs + Mempool (optional)
- **More comprehensive configuration** options
- **Different image**: `blockstream/bitcoind` instead of `dobtc/bitcoin`

### Variable Mapping from Ansible

See [values.yaml](values.yaml) for comprehensive mapping. Key changes:
- `bitcoin_chart_version: "2.1.6"` → `1.0.0` (custom chart)
- `bitcoin_release_name: bitcoin-core` → `bitcoin-stack`
- Chart repo: `hirosystems` → `k8s-charts`
- Added: `electrs_*` and `mempool_*` variables for new components
