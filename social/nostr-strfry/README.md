# Nostr Strfry Relay

Deploy a self-hosted Nostr relay using strfry on Kubernetes with Helm.

## Overview

strfry is a high-performance Nostr relay implementation optimized for speed and efficiency. It allows you to:
- Run your own Nostr relay for decentralized social networking
- Handle high-throughput event streams
- Store events in an LMDB database for fast queries
- Support Negentropy protocol for efficient sync
- Optionally provide NIP-05 verification service

This deployment serves as the **primary relay** for the crypto.example.com Nostr infrastructure.

## Prerequisites

- Kubernetes cluster with storage provisioner (Longhorn)
- **Storage:** 50GB+ for event database
- Helm 3.x installed
- Ingress controller (NGINX)
- cert-manager for TLS certificates
- Public DNS record for the relay

## Architecture

```
┌────────────────────────────────────────┐
│      Nostr Strfry Pod                  │
│  ┌──────────────────────────────────┐  │
│  │   strfry Container               │  │
│  │   - Port 7777: WebSocket         │  │
│  │   - LMDB database                │  │
│  │   - Volume: /app/strfry-db       │  │
│  └──────────────────────────────────┘  │
└────────────────────────────────────────┘
          │                    │
          ▼                    ▼
    ┌──────────┐        ┌──────────────┐
    │   PVC    │        │   Ingress    │
    │  (50GB)  │        │   (HTTPS)    │
    └──────────┘        └──────────────┘
                              │
                              ▼
                    nostr.crypto.example.com
```

## Installation

### 1. Create Namespace

```bash
kubectl create namespace nostr
```

### 2. Add Helm Repository

```bash
helm repo add k8s-charts https://kriegalex.github.io/k8s-charts/
helm repo update
```

### 3. Configure DNS

Set up DNS record for your relay:

```
# A record pointing to your cluster's ingress IP
nostr.crypto.example.com    A    <INGRESS_IP>
```

### 4. Customize Helm Values

Edit `custom-values.yaml` with your specific configuration:

```yaml
# Replica count
replicaCount: 1

# Image configuration
image:
  repository: dockurr/strfry
  pullPolicy: IfNotPresent
  tag: ""  # Use chart default

# Ingress configuration
ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: nostr.crypto.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - hosts:
        - nostr.crypto.example.com
      secretName: strfry-ingress-tls

# Resource limits
resources:
  limits:
    cpu: 500m
    memory: 1Gi
  requests:
    cpu: 100m
    memory: 256Mi

# Persistence configuration
persistence:
  enabled: true
  size: 50Gi
  storageClass: "longhorn"
  accessMode: ReadWriteOnce

# Relay configuration (NIP-11)
config:
  relay:
    info:
      name: "nostr.crypto.example.com"
      description: "main strfry relay provided by crypto.example.com"
      pubkey: "e78c8cf2030deb7e76dd096223b7795e2c1aab862a708bd1c5cccebdf21af45b"
      contact: ""
      icon: "https://image.nostr.build/19b2f3f232b0a962b2cc2bd0d74156235b126102e45a3fc3be93c8528e05e034.png"

# NIP-05 verification (optional)
nip05:
  enabled: false
  identities:
    kriegalex: e78c8cf2030deb7e76dd096223b7795e2c1aab862a708bd1c5cccebdf21af45b
  relays:
    e78c8cf2030deb7e76dd096223b7795e2c1aab862a708bd1c5cccebdf21af45b:
      - wss://nostr.crypto.example.com
      - wss://nostr-2.crypto.example.com

# Security contexts
podSecurityContext:
  fsGroup: 1000

securityContext:
  runAsUser: 1000
  runAsGroup: 1000
  runAsNonRoot: true
```

### 5. Install with Helm

```bash
helm upgrade --install nostr-strfry k8s-charts/nostr-strfry \
  --namespace nostr \
  --create-namespace \
  --version 1.1.2 \
  -f custom-values.yaml
```

### 6. Verify Deployment

```bash
# Check pod status
kubectl get pods -n nostr

# Check service
kubectl get svc -n nostr

# Check ingress
kubectl get ingress -n nostr

# View logs
kubectl logs -n nostr -l app.kubernetes.io/name=nostr-strfry -f
```

## Configuration Options

### Database Configuration

Configure LMDB database parameters:

```yaml
config:
  dbParams:
    maxreaders: 256  # Max concurrent readers
    mapsize: "10995116277760"  # 10TB default
    noReadAhead: false  # Disable read-ahead
```

### Event Filtering

Control what events are accepted:

```yaml
config:
  events:
    maxEventSize: "65536"  # Max event size (bytes)
    rejectEventsNewerThanSeconds: 900  # Reject future events
    rejectEventsOlderThanSeconds: "94608000"  # ~3 years
    maxNumTags: 2000  # Max tags per event
```

### Performance Tuning

Adjust thread counts for optimal performance:

```yaml
config:
  relay:
    numThreads:
      ingester: 3  # Route incoming requests
      reqWorker: 3  # Handle DB scans
      reqMonitor: 3  # Filter new events
      negentropy: 2  # Handle negentropy sync
```

### Negentropy Sync

Enable fast event synchronization:

```yaml
config:
  relay:
    negentropy:
      enabled: true
      maxSyncEvents: "1000000"  # Max events per sync
```

### Write Policy Plugin

Add custom event validation (advanced):

```yaml
config:
  relay:
    writePolicy:
      plugin: "/app/plugins/my-policy.sh"
```

## NIP-05 Verification Service

Enable NIP-05 verification for user handles:

### Enable NIP-05

```yaml
nip05:
  enabled: true
  identities:
    username: hexadecimal_pubkey
    alice: "abc123..."
    bob: "def456..."
  relays:
    hexadecimal_pubkey:
      - wss://nostr.crypto.example.com
      - wss://relay2.example.com
```

### Access NIP-05

Users can verify via:
```
https://nostr.crypto.example.com/.well-known/nostr.json?name=username
```

## Administration

### Check Relay Info

Test the relay's NIP-11 info:

```bash
curl -H "Accept: application/nostr+json" https://nostr.crypto.example.com/
```

### View Database Size

```bash
kubectl exec -n nostr <pod-name> -- du -sh /app/strfry-db
```

### Monitor Performance

```bash
# Check resource usage
kubectl top pod -n nostr

# View recent logs
kubectl logs -n nostr -l app.kubernetes.io/name=nostr-strfry --tail=100
```

### Database Statistics

```bash
# Execute strfry stats command
kubectl exec -n nostr <pod-name> -- strfry stats
```

### Backup Database

```bash
# Backup the LMDB database
kubectl exec -n nostr <pod-name> -- tar czf - /app/strfry-db > nostr-strfry-backup.tar.gz
```

### Export Events

Export all events to JSON:

```bash
kubectl exec -n nostr <pod-name> -- strfry export > events.jsonl
```

### Import Events

Import events from another relay:

```bash
cat events.jsonl | kubectl exec -i -n nostr <pod-name> -- strfry import
```

## Troubleshooting

### Pod Not Starting

```bash
kubectl describe pod -n nostr <pod-name>
kubectl logs -n nostr <pod-name>
```

Common issues:
- **PVC not binding**: Check Longhorn storage class availability
- **Permission denied**: Verify security contexts and fsGroup
- **LMDB errors**: Check database corruption or size limits

### Cannot Connect to Relay

Check WebSocket connectivity:

```bash
# Test ingress
kubectl get ingress -n nostr

# Check certificate
kubectl get certificate -n nostr

# Test WebSocket (using websocat or similar)
websocat wss://nostr.crypto.example.com/
```

### High Memory Usage

If the relay consumes too much memory, reduce concurrent connections:

```yaml
config:
  dbParams:
    maxreaders: 128  # Reduce from 256
  relay:
    numThreads:
      reqWorker: 2  # Reduce from 3
```

### Database Corruption

If LMDB database is corrupted:

```bash
# Stop the pod
kubectl scale deployment nostr-strfry -n nostr --replicas=0

# Restore from backup or rebuild database
# Then restart
kubectl scale deployment nostr-strfry -n nostr --replicas=1
```

## Monitoring

### Relay Health Checks

```bash
# Check if relay is responding
curl -I https://nostr.crypto.example.com/

# Check NIP-11 info
curl -H "Accept: application/nostr+json" https://nostr.crypto.example.com/ | jq .
```

### Event Statistics

```bash
# Get database statistics
kubectl exec -n nostr <pod-name> -- strfry stats

# Monitor event throughput
kubectl logs -n nostr -l app.kubernetes.io/name=nostr-strfry -f | grep "saved"
```

### Performance Metrics

Enable detailed logging:

```yaml
config:
  relay:
    logging:
      dbScanPerf: true  # Log DB scan performance
      invalidEvents: true  # Log rejected events
```

## Upgrade

```bash
helm repo update

helm upgrade nostr-strfry k8s-charts/nostr-strfry \
  --namespace nostr \
  --version <new-version> \
  -f custom-values.yaml
```

> **Note:** Always backup the database before upgrading!

## Uninstall

```bash
# Remove Helm release
helm uninstall nostr-strfry -n nostr

# Remove PVC (WARNING: Deletes all relay data)
kubectl delete pvc -n nostr -l app.kubernetes.io/name=nostr-strfry

# If you want to keep data, backup PVC first!
```

## Additional Resources

- [strfry GitHub](https://github.com/hoytech/strfry)
- [Nostr Protocol Documentation](https://nostr.com/)
- [NIP-11: Relay Information Document](https://github.com/nostr-protocol/nips/blob/master/11.md)
- [NIP-05: DNS-based Verification](https://github.com/nostr-protocol/nips/blob/master/05.md)
- [Negentropy Protocol](https://github.com/hoytech/negentropy)
- [Helm Chart Repository](https://github.com/kriegalex/k8s-charts)

## Network Configuration

This relay is part of the crypto.example.com Nostr infrastructure:
- **Primary relay**: nostr.crypto.example.com (strfry) - High-performance main relay
- **Backup relay**: nostr-2.crypto.example.com (rs-relay) - Lightweight backup

Both relays sync events and provide redundancy for the network.

## Performance Tips

1. **Increase mapsize** if database exceeds current limit:
   ```yaml
   dbParams:
     mapsize: "21990232555520"  # 20TB
   ```

2. **Adjust thread counts** based on CPU cores:
   ```yaml
   numThreads:
     ingester: 4
     reqWorker: 4
     reqMonitor: 4
   ```

3. **Enable compression** for bandwidth savings:
   ```yaml
   compression:
     enabled: true
     slidingWindow: true
   ```

4. **Tune query limits** to prevent abuse:
   ```yaml
   maxFilterLimit: 500  # Max records per filter
   maxSubsPerConnection: 20  # Max subscriptions
   ```
