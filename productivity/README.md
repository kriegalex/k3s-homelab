# Productivity Applications

This directory contains self-hosted productivity and collaboration tools.

## Applications

- **[nextcloud](nextcloud/)** - File sync, sharing, and collaboration platform
- **[paperless-ngx](paperless-ngx/)** - Document management system with OCR
- **[actual-budget](actual-budget/)** - Personal finance and budgeting tool
- **[n8n](n8n/)** - Workflow automation platform (alternative to Zapier)
- **[gitea](gitea/)** - Self-hosted Git service (alternative to GitHub)

## Use Cases

### Nextcloud

- **File Storage**: Replace Dropbox/Google Drive
- **Calendar/Contacts**: CalDAV/CardDAV sync
- **Collaboration**: Office documents, notes, tasks
- **Photo Backup**: Automatic phone photo uploads

### Paperless-ngx

- **Document Archival**: Scan and store receipts, invoices, contracts
- **OCR Processing**: Full-text search across all documents
- **Tagging System**: Organize documents by category/date/correspondent
- **Workflows**: Auto-tagging, email ingestion, mobile scanning

### Actual Budget

- **Budget Management**: Zero-based budgeting methodology
- **Bank Sync**: Import transactions via SimpleFIN
- **Multi-Device**: Web UI accessible from anywhere
- **Privacy**: Self-hosted, no cloud tracking

### n8n

- **Automation**: Trigger workflows on events (webhooks, schedules, polls)
- **Integrations**: 400+ nodes (Slack, GitHub, Nextcloud, etc.)
- **Custom Logic**: JavaScript code for complex transformations
- **Self-Hosted**: Full control over automation data

### Gitea

- **Git Hosting**: Private repositories for personal projects
- **Issue Tracking**: Built-in issue/project management
- **CI/CD**: Gitea Actions (GitHub Actions compatible)
- **Collaboration**: Pull requests, code review, wikis

## Shared Dependencies

### Database Layer

Several applications use PostgreSQL via [CloudNativePG](../database/cloudnative-pg/):

- **n8n**: Dedicated CNPG cluster (`n8n-cnpg-cluster.yaml`)
- **Nextcloud**: Shared PostgreSQL (can use CNPG or standalone)
- **Paperless-ngx**: Embedded PostgreSQL via Helm chart
- **Gitea**: Embedded PostgreSQL or external (configurable)

### NFS Storage

Applications using shared NFS storage:

- **Nextcloud**: `nfs-nextcloud-data` for user files
- **Paperless-ngx**: `nfs-paperless-media` for document storage

Apply NFS PVCs before deployment:

```bash
kubectl apply -f ../storage/nfs-shares/nfs-nextcloud-data.yaml
kubectl apply -f ../storage/nfs-shares/nfs-paperless-media.yaml
```

### Ingress Rules

HTTPS ingress configurations located at:

```bash
../ingress/rules/productivity/gitea/
../ingress/rules/productivity/nextcloud/
```

Other applications (n8n, paperless-ngx, actual-budget) may have ingress defined in Helm values.

## Installation Order

1. **Database Layer** (if using CNPG):
   ```bash
   kubectl apply -f ../database/cloudnative-pg/
   kubectl apply -f n8n/cnpg-cluster.yaml
   ```

2. **NFS Storage** (if using shared storage):
   ```bash
   kubectl apply -f ../storage/nfs-shares/nfs-nextcloud-data.yaml
   kubectl apply -f ../storage/nfs-shares/nfs-paperless-media.yaml
   ```

3. **Deploy Applications**:
   - Gitea (lightweight, no external dependencies)
   - Actual Budget (standalone, minimal resources)
   - n8n (requires CNPG cluster ready)
   - Nextcloud (requires storage ready)
   - Paperless-ngx (requires storage ready)

## Configuration Tips

### Nextcloud Security

Nextcloud requires HTTPS and proper trusted domains configuration:

```yaml
nextcloud:
  configs:
    custom.config.php: |-
      <?php
      $CONFIG = array (
        'trusted_domains' => array (
          'nextcloud.yourdomain.com',
        ),
        'overwriteprotocol' => 'https',
      );
```

See [nextcloud/README.md](nextcloud/README.md) for full configuration.

### Paperless-ngx OCR

Paperless-ngx performs OCR processing. Ensure adequate resources:

- **CPU**: 2+ cores for OCR processing
- **Memory**: 2GB+ for document processing
- **GPU**: Optional Intel QuickSync for faster processing

### n8n Workflows

n8n requires persistent database for workflow state:

- Uses CloudNativePG cluster for high availability
- Workflow data stored in PostgreSQL
- Credentials encrypted with `N8N_ENCRYPTION_KEY`

Store the encryption key securely:

```bash
kubectl create secret generic n8n-secrets \
  --from-literal=encryption-key='your-secure-key'
```

### Gitea Runners

Enable Gitea Actions for CI/CD:

```yaml
gitea:
  actions:
    enabled: true
```

Register act runners separately for job execution.

## Ingress and SSL

All productivity apps should be exposed via HTTPS with cert-manager:

```yaml
annotations:
  cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
    - hosts:
        - app.yourdomain.com
      secretName: app-tls
```

See [ingress README](../ingress/README.md) for cert-manager setup.

## Backup Strategy

Critical data requires regular backups:

- **Nextcloud**: User files (NFS volume) + PostgreSQL database
- **Paperless-ngx**: Document media (NFS volume) + PostgreSQL database
- **n8n**: Workflow database (PostgreSQL CNPG handles this)
- **Gitea**: Repository data + PostgreSQL database

Use [k8up](../backup/k8up/) for automated PVC and database backups.

## Resource Requirements

Typical resource allocations:

| Application    | CPU Request | Memory Request | Storage      |
|---------------|-------------|----------------|--------------|
| Nextcloud     | 1 core      | 2GB           | 50GB+ (data) |
| Paperless-ngx | 1 core      | 2GB           | 20GB+ (docs) |
| Actual Budget | 100m        | 128MB         | 1GB          |
| n8n           | 500m        | 1GB           | 5GB          |
| Gitea         | 500m        | 1GB           | 10GB+ (repos)|

## Cross-References

- **Database**: [database/cloudnative-pg](../database/cloudnative-pg/)
- **NFS Storage**: [nfs-storage](../storage/nfs-shares/)
- **Ingress Rules**: [ingress/rules/productivity](../ingress/rules/productivity/)
- **Backup**: [backup/k8up](../backup/k8up/)

## Troubleshooting

### Nextcloud Maintenance Mode

Reset maintenance mode if stuck:

```bash
kubectl exec -n nextcloud <pod-name> -- php occ maintenance:mode --off
```

### Paperless-ngx OCR Stuck

Check consumer logs:

```bash
kubectl logs -n paperless <pod-name> -c consumer
```

### n8n Database Connection

Verify CNPG cluster is running:

```bash
kubectl get cluster -n n8n
kubectl get pods -n n8n
```

### Gitea Migration Issues

Check migration logs:

```bash
kubectl logs -n gitea <pod-name> | grep migration
```

## Documentation

Each application directory contains:

- **README.md** - Installation and configuration guide
- **custom-values.yaml** - Helm value overrides
- **secrets-template.yaml** - Secret configuration template (if applicable)

Navigate to individual application folders for detailed instructions.
