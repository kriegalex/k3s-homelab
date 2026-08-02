# Nostr RS Relay

Deploy a self-hosted Nostr relay using nostr-rs-relay on Kubernetes with Helm.

## Overview

nostr-rs-relay is a lightweight, high-performance Nostr relay implementation written in Rust. It allows you to:
- Run your own Nostr relay for decentralized social networking
- Control what events are stored and relayed
- Configure rate limits and access policies
- Participate in the Nostr protocol network

This deployment serves as a **backup relay** for the crypto.example.com Nostr infrastructure.

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
│      Nostr RS Relay Pod                │
│  ┌──────────────────────────────────┐  │
│  │   nostr-rs-relay Container       │  │
│  │   - Port 8080: WebSocket         │  │
│  │   - SQLite database              │  │
│  │   - Volume: /app (DB storage)    │  │
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
                    nostr-2.crypto.example.com
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
nostr-2.crypto.example.com    A    <INGRESS_IP>
```

### 4. Customize Helm Values

Edit `values.yaml` with your specific configuration:

```yaml
# Replica count
replicaCount: 1

# Image configuration
image:
  repository: scsibug/nostr-rs-relay
  pullPolicy: IfNotPresent
  tag: ""  # Use chart default

# Ingress configuration
ingress:
  enabled: true
  className: "traefik"
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: nostr-2.crypto.example.com
      paths:
        - path: /
          pathType: ImplementationSpecific
  tls:
    - hosts:
        - nostr-2.crypto.example.com
      secretName: rsrelay-ingress-tls

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
  info:
    relay_url: "wss://nostr-2.crypto.example.com/"
    name: "nostr-2.crypto.example.com"
    description: "rs-relay backup relay provided by crypto.example.com"
    pubkey: "e78c8cf2030deb7e76dd096223b7795e2c1aab862a708bd1c5cccebdf21af45b"
    relay_icon: "https://image.nostr.build/19b2f3f232b0a962b2cc2bd0d74156235b126102e45a3fc3be93c8528e05e034.png"

  # Network settings
  network:
    address: "0.0.0.0"
    port: 8080

  # Rate limits
  limits:
    messages_per_sec: 100
    limit_scrapers: true       # reject kind-only/author-only broad scans

  # Options
  options:
    reject_future_seconds: 1800

# Security contexts
podSecurityContext:
  fsGroup: 1000
  runAsUser: 1000
  runAsGroup: 1000

securityContext:
  runAsUser: 1000
  runAsGroup: 1000
  runAsNonRoot: true
```

### 5. Install with Helm

```bash
helm upgrade --install nostr-rs-relay k8s-charts/nostr-rs-relay \
  --namespace nostr \
  --create-namespace \
  --version 1.0.1 \
  -f values.yaml
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
kubectl logs -n nostr -l app.kubernetes.io/name=nostr-rs-relay -f
```

## Configuration Options

### Rate Limiting

Control event creation rate:

```yaml
config:
  limits:
    messages_per_sec: 100  # Events per second
    subscriptions_per_min: 0  # 0 = unlimited
```

### Event Filtering

Configure event acceptance:

```yaml
config:
  options:
    reject_future_seconds: 1800  # Reject events from future
  limits:
    limit_scrapers: true  # Block scraper-like (imprecise) queries
```

### Authorization

Restrict who can publish (optional):

```yaml
config:
  authorization:
    pubkey_whitelist:
      - "hexadecimal_pubkey_1"
      - "hexadecimal_pubkey_2"
    nip42_auth: true  # Require NIP-42 authentication
```

### Verified Users (NIP-05)

Enable NIP-05 verification:

```yaml
config:
  verified_users:
    mode: "enabled"  # enabled/passive/disabled
    domain_whitelist:
      - "example.com"
    verify_expiration: "1 week"
```

## Administration

### Check Relay Info

Test the relay's NIP-11 info:

```bash
curl -H "Accept: application/nostr+json" https://nostr-2.crypto.example.com/
```

### View Database Size

```bash
kubectl exec -n nostr <pod-name> -- du -sh /app/nostr.db
```

### Monitor Performance

```bash
# Check resource usage
kubectl top pod -n nostr

# View recent logs
kubectl logs -n nostr -l app.kubernetes.io/name=nostr-rs-relay --tail=100
```

### Backup Database

```bash
# Backup the SQLite database
kubectl exec -n nostr <pod-name> -- tar czf - /app > nostr-rs-relay-backup.tar.gz
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

### Cannot Connect to Relay

Check WebSocket connectivity:

```bash
# Test ingress
kubectl get ingress -n nostr

# Check certificate
kubectl get certificate -n nostr

# Test WebSocket (using websocat or similar)
websocat wss://nostr-2.crypto.example.com/
```

### High Memory Usage

If the relay consumes too much memory:

```yaml
config:
  database:
    max_conn: 4  # Reduce max connections
  limits:
    max_blocking_threads: 8  # Reduce threads
```

### High Disk Read / Scraper Load

Symptom: recurring multi-second read bursts (tens to ~200 MB/s) on the
worker nodes, amplified across all workers because the database PVC is a
Longhorn volume with 3 replicas. Cause: scrapers/indexers issuing broad
`REQ` filters (kind-only / author-only / no precise terms) that force
SQLite to scan the multi-GB event database, plus high-volume bulk pulls
(tens of thousands of events per connection).

Mitigation (already applied in `values.yaml`):

```yaml
config:
  limits:
    limit_scrapers: true     # reject imprecise broad-scan requests
```

`limit_scrapers` is the effective lever (verified against nostr-rs-relay
source — it filters the request itself, independent of source IP). The
only global DB-concurrency cap on SQLite is `config.database.max_conn`
(default 8); lowering it throttles legitimate readers too, so only
consider it if spikes persist after `limit_scrapers`.

The relay sees real client IPs: the Traefik Service runs with
`externalTrafficPolicy=Local` (MetalLB L2), so the client IP is not
SNAT'd, and `config.network.remote_ip_header: x-forwarded-for` makes the
relay read it from Traefik's X-Forwarded-For header. This enables per-IP
limits and meaningful access logs. `limit_scrapers` works regardless of
source IP, so the read-spike mitigation is independent.

## Monitoring

### Relay Health Checks

```bash
# Check if relay is responding
curl -I https://nostr-2.crypto.example.com/

# Check NIP-11 info
curl -H "Accept: application/nostr+json" https://nostr-2.crypto.example.com/ | jq .
```

### Event Statistics

Monitor via logs:

```bash
kubectl logs -n nostr -l app.kubernetes.io/name=nostr-rs-relay | grep "events saved"
```

## Upgrade

```bash
helm repo update

helm upgrade nostr-rs-relay k8s-charts/nostr-rs-relay \
  --namespace nostr \
  --version <new-version> \
  -f values.yaml
```

> **Note:** Always backup the database before upgrading!

## Uninstall

```bash
# Remove Helm release
helm uninstall nostr-rs-relay -n nostr

# Remove PVC (WARNING: Deletes all relay data)
kubectl delete pvc -n nostr -l app.kubernetes.io/name=nostr-rs-relay

# If you want to keep data, backup PVC first!
```

## Additional Resources

- [nostr-rs-relay GitHub](https://github.com/scsibug/nostr-rs-relay)
- [Nostr Protocol Documentation](https://nostr.com/)
- [NIP-11: Relay Information Document](https://github.com/nostr-protocol/nips/blob/master/11.md)
- [Helm Chart Repository](https://github.com/kriegalex/k8s-charts)

## Network Configuration

This relay is part of the crypto.example.com Nostr infrastructure:
- **Primary relay**: nostr.crypto.example.com (strfry)
- **Backup relay**: nostr-2.crypto.example.com (rs-relay)

Both relays sync events and provide redundancy for the network.
