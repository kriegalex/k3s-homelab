# Bluesky Personal Data Server (PDS)

Deploy a self-hosted Bluesky Personal Data Server on Kubernetes using Helm.

## Overview

A Bluesky PDS (Personal Data Server) allows you to:
- Host your own identity on the AT Protocol (ATProto) network
- Control your own data and social graph
- Create and manage user accounts for yourself or others
- Participate in the decentralized Bluesky network

This is useful for:
- Self-hosting your Bluesky identity
- Running a private or community Bluesky server
- Learning about the AT Protocol
- Supporting decentralization of social media

> **⚠️ WARNING:** This Helm chart deployment has been minimally tested and never used in production. Use at your own risk and thoroughly test in a non-production environment before deploying to production. Always verify the configuration and ensure you have proper backups.

## Prerequisites

- Kubernetes cluster with storage provisioner
- **Storage:** 10GB+ for user data (can grow over time)
- Helm 3.x installed
- **Required:** Ingress controller with wildcard subdomain support (for user handles)
- **Required:** cert-manager for TLS certificates
- **Required:** Public DNS with wildcard subdomain (e.g., `*.pds.example.com`)
- **Optional:** SMTP server for email notifications

## Architecture

```
┌────────────────────────────────────────────────┐
│         Bluesky PDS Pod                        │
│  ┌──────────────────────────────────────────┐  │
│  │   Bluesky PDS Container                  │  │
│  │   - Port 3000: HTTP API                  │  │
│  │   - AT Protocol endpoints                │  │
│  │   - Admin interface                      │  │
│  │   - Volume: /pds (user data + blocks)    │  │
│  └──────────────────────────────────────────┘  │
└────────────────────────────────────────────────┘
          │                    │
          ▼                    ▼
    ┌──────────┐        ┌──────────────┐
    │   PVC    │        │   Ingress    │
    │  (10GB+) │        │  (wildcard)  │
    └──────────┘        └──────────────┘
                              │
                              ▼
                    pds.example.com
                    *.pds.example.com
                    (user handles)
```

## Installation

### 1. Create Namespace

```bash
kubectl create namespace bluesky-pds
```

### 2. Add Helm Repository

```bash
helm repo add nerkho https://charts.nerkho.ch
helm repo update
```

### 3. Configure DNS

**Critical:** Set up wildcard DNS BEFORE deployment:

```
# A records pointing to your cluster's ingress IP
pds.example.com       A    <INGRESS_IP>
*.pds.example.com     A    <INGRESS_IP>
```

The wildcard subdomain is required for user handles (e.g., `alice.pds.example.com`).

### 4. Generate Secrets

Generate the required secrets:

```bash
# JWT secret (for API tokens)
JWT_SECRET=$(openssl rand --hex 16)

# PLC rotation key (for identity management)
PLC_KEY=$(openssl ecparam --name secp256k1 --genkey --noout --outform DER | \
  tail --bytes=+8 | head --bytes=32 | xxd --plain --cols 32)

# Admin password
ADMIN_PASSWORD=$(openssl rand --hex 16)

# Display secrets (SAVE THESE!)
echo "JWT Secret: $JWT_SECRET"
echo "PLC Rotation Key: $PLC_KEY"
echo "Admin Password: $ADMIN_PASSWORD"
```

> **Important:** Save these secrets securely! You'll need them for disaster recovery.

### 5. Create Kubernetes Secret

Create `secrets.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: bluesky-pds-secrets
  namespace: bluesky-pds
type: Opaque
stringData:
  jwtSecret: "<JWT_SECRET>"
  plcRotationKey: "<PLC_KEY>"
  adminPassword: "<ADMIN_PASSWORD>"
  # Optional: SMTP URL for email
  # emailSmtpUrl: "smtps://user:password@smtp.example.com:465/"
```

Apply it:
```bash
kubectl apply -f secrets.yaml
```

### 6. Customize Helm Values

Create `values.yaml`:

```yaml
# Replica count
replicaCount: 1

# PDS image
image:
  repository: ghcr.io/bluesky-social/pds
  pullPolicy: IfNotPresent
  # tag: ""  # Use chart default

# PDS configuration
pds:
  config:
    # CRITICAL: Your public hostname
    hostname: pds.example.com  # CHANGE THIS!

    # Use the Kubernetes secret we created
    secrets:
      existingSecret: "bluesky-pds-secrets"

    # Data directories
    dataDir: "/pds"
    blobstoreLocation: "/pds/blocks"

    # AT Protocol network endpoints
    didPlcUrl: "https://plc.directory"
    bskyAppViewUrl: "https://api.bsky.app"
    bskyAppViewDid: "did:web:api.bsky.app"
    reportSvcUrl: "https://mod.bsky.app"
    reportSvcDid: "did:plc:ar7c4by46qjdydhdevvrndac"
    crawlers: "https://bsky.network"

    # Email from address (if SMTP enabled)
    pdsEmailFromAddress: "noreply@example.com"

  # Persistent storage
  dataStorage:
    size: 10Gi  # Increase as needed
    mountPath: "/pds"
    storageClass: "longhorn"  # or your storage class
    selector: null

# Service
service:
  type: ClusterIP
  port: 3000

# Ingress - REQUIRED for PDS to work
ingress:
  enabled: true
  className: "traefik"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    # HTTP→HTTPS redirect via Traefik Middleware (ingress/traefik/middlewares/redirect-https.yaml).
    traefik.ingress.kubernetes.io/router.middlewares: "traefik-redirect-https@kubernetescrd"
    # Body size: Traefik streams request bodies by default with no cap, so
    # media uploads are unconstrained without an explicit Buffering middleware.
  hosts:
    # Main PDS endpoint
    - host: pds.example.com
      paths:
        - path: /
          pathType: Prefix
    # Wildcard for user handles (e.g., alice.pds.example.com)
    - host: "*.pds.example.com"
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: bluesky-pds-tls
      hosts:
        - pds.example.com
        - "*.pds.example.com"

# Resource limits
resources:
  requests:
    memory: 512Mi
    cpu: 200m
  limits:
    memory: 2Gi
    cpu: 1000m

# Service account
serviceAccount:
  create: true
  annotations: {}
  name: ""

# Security contexts
podSecurityContext: {}
securityContext: {}

# Node placement (optional)
nodeSelector: {}
tolerations: []
affinity: {}
```

### 7. Install with Helm

```bash
helm upgrade --install bluesky-pds nerkho/bluesky-pds \
  --namespace bluesky-pds \
  --create-namespace \
  --version 0.3.0 \
  -f values.yaml
```

### 8. Verify Deployment

```bash
# Check pod status
kubectl get pods -n bluesky-pds

# Check service
kubectl get svc -n bluesky-pds

# Check ingress
kubectl get ingress -n bluesky-pds

# View logs
kubectl logs -n bluesky-pds -l app.kubernetes.io/name=bluesky-pds -f
```

## Post-Installation Setup

### 1. Access Admin Interface

Navigate to: `https://pds.example.com/`

You should see the Bluesky PDS welcome page.

### 2. Retrieve Admin Credentials

```bash
# Get admin password from secret
kubectl get secret bluesky-pds-secrets -n bluesky-pds -o jsonpath='{.data.adminPassword}' | base64 -d
echo
```

### 3. Configure Your DID (Decentralized Identifier)

The PDS will automatically generate a DID for your server. You can view it via the admin interface or API.

### 4. Create Your First Account

Use the PDS admin interface or API to create accounts:

```bash
# Using pdsadmin.sh (if available)
kubectl exec -n bluesky-pds <pod-name> -- \
  /app/pdsadmin.sh account create
```

Or use the admin interface at `https://pds.example.com/admin`

## Configuration Options

### SMTP for Email Notifications

To enable email notifications (for password resets, etc.):

1. Update the secret with SMTP URL:
```yaml
stringData:
  emailSmtpUrl: "smtps://user:password@smtp.example.com:465/"
  # or for STARTTLS:
  # emailSmtpUrl: "smtp://user:password@smtp.example.com:587/"
```

2. Update values:
```yaml
pds:
  config:
    pdsEmailFromAddress: "noreply@pds.example.com"
```

### Resource Allocation

Adjust based on your user count:

```yaml
resources:
  requests:
    memory: 512Mi  # Minimum
    cpu: 200m
  limits:
    memory: 4Gi  # For larger instances
    cpu: 2000m
```

### Storage Size

Increase storage for more users or media:

```yaml
pds:
  dataStorage:
    size: 50Gi  # Adjust as needed
```

## Administration

### Using pdsadmin.sh

Download the admin script:

```bash
wget https://raw.githubusercontent.com/bluesky-social/pds/main/pdsadmin.sh
chmod +x pdsadmin.sh
```

Common commands:

```bash
# Create account
kubectl exec -n bluesky-pds <pod-name> -- /app/pdsadmin.sh account create

# List accounts
kubectl exec -n bluesky-pds <pod-name> -- /app/pdsadmin.sh account list

# Reset password
kubectl exec -n bluesky-pds <pod-name> -- /app/pdsadmin.sh account reset-password <handle>
```

### Backup and Recovery

#### Backup Data

```bash
# Backup the PVC
kubectl get pvc -n bluesky-pds

# Using k8up or velero
# Or manually copy from the pod
kubectl exec -n bluesky-pds <pod-name> -- tar czf - /pds > pds-backup.tar.gz
```

#### Important: Backup Secrets!

```bash
# Backup the secrets (CRITICAL for recovery)
kubectl get secret bluesky-pds-secrets -n bluesky-pds -o yaml > bluesky-pds-secrets-backup.yaml
```

### Restore from Backup

1. Restore the PVC data
2. Restore the secrets
3. Deploy PDS with Helm pointing to restored PVC

## Troubleshooting

### Pod Not Starting

```bash
kubectl describe pod -n bluesky-pds <pod-name>
kubectl logs -n bluesky-pds <pod-name>
```

Common issues:
- **PVC not binding**: Check storage class availability
- **Secrets not found**: Ensure `bluesky-pds-secrets` exists
- **Image pull errors**: Check network connectivity

### Cannot Access PDS

Check ingress and DNS:

```bash
# Check ingress
kubectl get ingress -n bluesky-pds
kubectl describe ingress -n bluesky-pds <ingress-name>

# Test DNS
nslookup pds.example.com
nslookup test.pds.example.com  # Test wildcard

# Test TLS certificate
curl -v https://pds.example.com/
```

### Certificate Issues

If using cert-manager:

```bash
# Check certificate
kubectl get certificate -n bluesky-pds

# Check certificate request
kubectl get certificaterequest -n bluesky-pds

# Describe for errors
kubectl describe certificate bluesky-pds-tls -n bluesky-pds
```

### Federation Issues

Check connectivity to AT Protocol network:

```bash
# Test PLC directory access
kubectl exec -n bluesky-pds <pod-name> -- curl https://plc.directory

# Check logs for federation errors
kubectl logs -n bluesky-pds <pod-name> | grep -i error
```

## Monitoring

### Check PDS Health

```bash
# Health endpoint
curl https://pds.example.com/xrpc/_health

# Check resource usage
kubectl top pod -n bluesky-pds
```

### View Metrics

```bash
# Disk usage
kubectl exec -n bluesky-pds <pod-name> -- df -h /pds

# Account count (via logs or admin interface)
kubectl logs -n bluesky-pds <pod-name> | grep account
```

## Upgrade

```bash
helm repo update

helm upgrade bluesky-pds nerkho/bluesky-pds \
  --namespace bluesky-pds \
  --version <new-version> \
  -f values.yaml
```

> **Note:** Always backup before upgrading!

## Uninstall

```bash
# Remove Helm release
helm uninstall bluesky-pds -n bluesky-pds

# Remove namespace (WARNING: Deletes PVC)
kubectl delete namespace bluesky-pds

# If you want to keep data, backup PVC first!
```

## Security Considerations

1. **Secrets Management**:
   - Use strong, randomly generated secrets
   - Store secrets securely (backup encrypted)
   - Rotate secrets periodically
   - Never commit secrets to version control

2. **Network Security**:
   - Always use TLS (HTTPS) via cert-manager
   - Configure firewall rules for ingress only
   - Consider network policies for pod isolation

3. **Access Control**:
   - Use strong admin password
   - Limit account creation (invite-only mode)
   - Monitor account registrations
   - Implement rate limiting at ingress level

4. **Data Protection**:
   - Regular backups of PVC and secrets
   - Test restore procedures
   - Monitor disk usage
   - Consider backup encryption

5. **Federation Security**:
   - Keep PDS software updated
   - Monitor AT Protocol security advisories
   - Review moderation settings
   - Configure appropriate crawlers/relays

## Additional Resources

- [Bluesky PDS Official Docs](https://github.com/bluesky-social/pds)
- [AT Protocol Documentation](https://atproto.com/docs)
- [Helm Chart by nerkho](https://github.com/nerkho/charts)
- [Self-Hosted PDS on K8s Guide](https://nerkho.ch/blog/self-hosted-pds-on-k8s/)
- [Bluesky API Reference](https://docs.bsky.app/)

## Migration from k3s-ansible

This deployment is migrated from [k3s-ansible](https://github.com/kriegalex/k3s-ansible) (refactor-backup branch).

Key differences:
- **Manual Helm deployment** instead of Ansible automation
- **Manual secret generation** instead of automatic (for better control)
- **Explicit configuration** in values files
- **Better documentation** for setup and troubleshooting

### Variable Mapping from Ansible

| Ansible Variable | Helm Value | Notes |
|-----------------|------------|-------|
| `bluesky_pds_enabled` | N/A | Manual deployment control |
| `bluesky_pds_namespace` | `--namespace` flag | Namespace: bluesky-pds |
| `bluesky_pds_release_name` | Release name | Default: bluesky-pds |
| `bluesky_pds_chart_version` | `--version` flag | Chart version: 0.3.0 |
| `bluesky_pds_subdomain` | `pds.config.hostname` | Full FQDN required |
| `bluesky_pds_fqdn` | `pds.config.hostname` | Direct mapping |
| `bluesky_pds_jwt_secret` | In K8s secret | `bluesky-pds-secrets` |
| `bluesky_pds_plc_rotation_key_secret` | In K8s secret | `bluesky-pds-secrets` |
| `bluesky_pds_admin_password` | In K8s secret | `bluesky-pds-secrets` |
| `bluesky_pds_persistence_enabled` | `pds.dataStorage.*` | Always enabled |
| `bluesky_pds_persistence_storage_class` | `pds.dataStorage.storageClass` | Direct mapping |
| `bluesky_pds_persistence_size` | `pds.dataStorage.size` | Direct mapping |
| `bluesky_pds_service_type` | `service.type` | Direct mapping |
| `bluesky_pds_service_port` | `service.port` | Direct mapping |
| `bluesky_pds_ingress_enabled` | `ingress.enabled` | Direct mapping |
| `bluesky_pds_ingress_class_name` | `ingress.className` | Direct mapping |
| `bluesky_pds_tls_enabled` | `ingress.tls` | TLS config |
| `bluesky_pds_smtp_*` | `emailSmtpUrl` in secret | Combined into URL |
| `bluesky_pds_resources_*` | `resources.*` | Direct mapping |
