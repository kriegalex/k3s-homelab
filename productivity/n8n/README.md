# N8n

[N8n](https://n8n.io/) is a workflow automation tool with a visual editor. It's an alternative to Zapier, Integromat, etc.

## TL;DR

```bash
kubectl create namespace n8n
kubectl apply -f postgresql.yaml -n n8n
kubectl apply -f n8n-secrets.yaml -n n8n  # Create encryption key secret
# Wait for database to be ready
kubectl wait --for=condition=Ready cluster/n8n-db -n n8n --timeout=300s
helm install n8n oci://8gears.container-registry.com/library/n8n --version 2.0.1 -f values.yaml -n n8n
```

## Prerequisites

- Kubernetes cluster
- Helm 3.0+
- PV provisioner support in the cluster (for persistence)
- CloudNativePG operator installed in the cluster
- S3-compatible storage for database backups (configured at http://10.0.0.7:8010)

## Installing the Chart

To install the chart with the release name `n8n`:

```bash
kubectl create namespace n8n
# First deploy the PostgreSQL database
kubectl apply -f postgresql.yaml -n n8n
# Create the encryption key secret (update the key first!)
kubectl apply -f n8n-secrets.yaml -n n8n
# Wait for database to be ready
kubectl wait --for=condition=Ready cluster/n8n-db -n n8n --timeout=300s
# Then deploy n8n
helm -n n8n upgrade --install n8n oci://8gears.container-registry.com/library/n8n -f custom-values.yaml
```

## Configuration

### Security Setup

**⚠️ IMPORTANT**: Before deploying, you must generate a secure encryption key:

```bash
# Generate a secure encryption key
openssl rand -base64 32

# Encode it for Kubernetes secret
echo -n "your-generated-key-here" | base64

# Update the encryption-key value in n8n-secrets.yaml
```

### Database

The configuration now uses the official structure with CloudNativePG. Key changes made:

- **Database connection**: Now uses the CNPG-generated `n8n-db-app` secret for database authentication
- **SSL enabled**: Database connections now use SSL with CA certificate validation
- **Connection pooling**: Configured with a pool size of 10 connections
- **CA certificate mounting**: The CNPG CA certificate is mounted into the container for SSL verification

**Important Notes:**
1. The database password is now automatically managed by CloudNativePG via the `n8n-db-app` secret
2. SSL is enabled by default, requiring the CA certificate to be available
3. The configuration follows the official n8n Helm chart structure with the `main` wrapper

Make sure to:
1. Generate and configure the encryption key secret (see Security Setup above)
2. Ensure CloudNativePG is installed and the cluster is ready before deploying n8n
3. The CA certificate secret (`n8n-db-ca`) should be automatically created by CloudNativePG

If you prefer to disable SSL (not recommended for production):
```yaml
main:
  config:
    db:
      postgresdb:
        ssl:
          enabled: false
```

#### Database Backups

The PostgreSQL cluster is configured to automatically back up to an S3-compatible storage. The configuration assumes:

- An S3-compatible service is running at http://10.0.0.7:8010
- A bucket named `n8n-backups` exists on this service
- Credentials are provided through the `n8n-db-backup-credentials` secret

Before deploying, make sure:
1. The S3 service is accessible
2. The bucket exists or can be auto-created
3. You've created the secret with valid S3 credentials:

```bash
kubectl create secret generic n8n-db-backup-credentials -n n8n \
  --from-literal=ACCESS_KEY_ID=your_access_key \
  --from-literal=ACCESS_SECRET_KEY=your_secret_key
```

### Ingress

Edit the values.yaml file to set your domain in the `ingress.hosts` section.

### Persistence

The chart mounts a Persistent Volume for storing n8n data. You can change the storage class and size in the values.yaml file.

#### Using a Pre-defined PVC

If you prefer to create the PVC separately before deploying n8n, you can:

1. Apply the provided persistent-volume.yaml:
```bash
kubectl apply -f persistent-volume.yaml -n n8n
```

2. Uncomment the `existingClaim` lines in values.yaml to use this PVC instead of creating a new one.

### Security

Make sure to change the `n8n.encryption.key` in values.yaml to a secure value. This key is used to encrypt sensitive data.
```

## Resources

For more information on configuring n8n, see the [official n8n documentation](https://docs.n8n.io/).

For CloudNativePG configuration options, refer to the [CloudNativePG documentation](https://cloudnative-pg.io/documentation/).
