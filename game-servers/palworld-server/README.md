# Deploy Palworld Server

**Chart Version:** 1.1.0+ (supports existingSecret for secure password management)

## Persistent Storage

Create the PersistentVolumeClaim:

```bash
kubectl apply -f palworld-server-pvc.yaml
```

This creates a Longhorn-backed persistent volume with automatic replication and snapshot support.

## Setup Secrets

### Create Secrets from Template

1. **Copy and edit the secrets template:**
```bash
cp secrets-template.yaml secrets.yaml
# Edit secrets.yaml and set your server passwords
```

2. **Apply the secrets:**
```bash
kubectl create namespace game-servers
kubectl apply -f secrets.yaml
```

### Alternative: Create Secret via Command Line

```bash
kubectl create namespace game-servers

kubectl create secret generic palworld-server-credentials \
  --from-literal=ADMIN_PASSWORD='your-admin-password' \
  --from-literal=SERVER_PASSWORD='your-server-password' \
  --namespace=game-servers
```

**Note:** Keys must be `ADMIN_PASSWORD` and `SERVER_PASSWORD` (uppercase) as these are the environment variable names expected by the Palworld Docker container.

## Install Server using Helm

```bash
# Add repository
helm repo add k8s-charts https://kriegalex.github.io/k8s-charts/
helm repo update

# Install using custom values (which references the existing secret)
helm upgrade --install palworld-server k8s-charts/palworld-server \
  --namespace game-servers \
  --create-namespace \
  --version 1.1.0 \
  -f values.yaml
```

## How It Works

The chart (v1.1.0+) supports `secret.existingSecret` to reference a pre-created Kubernetes secret for passwords. This approach:

✅ **Keeps passwords out of version control** - Secrets are never committed to Git
✅ **Uses Kubernetes-native secret management** - Leverages built-in security features
✅ **Follows Docker container requirements** - Secret keys must match environment variable names (`ADMIN_PASSWORD`, `SERVER_PASSWORD`)

The values.yaml file references the secret:
```yaml
secret:
  existingSecret: palworld-server-credentials
server:
  adminPassword: ""  # Empty - will use secret
  password: ""       # Empty - will use secret
```