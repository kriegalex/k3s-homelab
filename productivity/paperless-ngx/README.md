# Paperless-ngx

## Setup Secrets

⚠️ **IMPORTANT:** Never commit secrets to git. All password values must be stored in Kubernetes secrets.

### Create Secrets from Template

1. **Copy and edit the secrets template:**
```bash
cp secrets-template.yaml secrets.yaml
# Edit secrets.yaml and replace all CHANGE_ME_* placeholders
```

2. **Generate secure passwords:**
```bash
# For DB and Redis passwords
openssl rand -base64 32

# For secret key (longer)
openssl rand -base64 64
```

3. **Apply the secrets:**
```bash
kubectl create namespace paperless
kubectl apply -f secrets.yaml
```

### Alternative: Create Secrets via Command Line

```bash
kubectl create namespace paperless

# Database credentials (only needed if using Bitnami PostgreSQL subchart)
kubectl create secret generic paperless-db-credentials \
  --from-literal=password="$(openssl rand -base64 32)" \
  --namespace=paperless

# Redis credentials
kubectl create secret generic paperless-redis-credentials \
  --from-literal=redis-password="$(openssl rand -base64 32)" \
  --namespace=paperless

# Paperless application secrets
kubectl create secret generic paperless-secrets \
  --from-literal=PAPERLESS_SECRET_KEY="$(openssl rand -base64 64)" \
  --from-literal=PAPERLESS_ADMIN_USER='kriegalex' \
  --from-literal=PAPERLESS_ADMIN_PASSWORD="$(openssl rand -base64 32)" \
  --from-literal=PAPERLESS_ADMIN_MAIL='your-email@example.com' \
  --from-literal=PAPERLESS_DBPASS="$(openssl rand -base64 32)" \
  --namespace=paperless
```

## Persistence (without longhorn)

We manage everything manually to avoid PVCs binding to the wrong PV. Also, a homelab K8S is not really a cloud native kubernetes cluster that dynamically asks storage from a cloud service using `storageClass`.

```
kubectl -n paperless apply -f paperless-media-pv.yaml -f paperless-media-pvc.yaml
kubectl -n paperless apply -f paperless-psql-pv.yaml -f paperless-psql-pvc.yaml
```

In my setup, I reuse an existing nfs share with subpaths for the `CONSUME` and `EXPORT` folders. `DATA` is in the [same path](https://docs.paperless-ngx.com/configuration/#PAPERLESS_MEDIA_ROOT) as `MEDIA`.

> Note: make sure the files to consume in the NFS share have the proper permissions. In unRAID, by default, this means that the files are owned by `nobody:users` instead of `paperless:paperless` (1000:1000).
> 
> Make sure any older file to consume is copied with the archive option (i.e. `cp -a` or `rsync -a`).

### Setup permissions (worker nodes)

```
sudo mkdir -p /mnt/paperless/media
sudo mkdir -p /mnt/paperless/psql
sudo chown 1001:1001 /mnt/paperless/psql
```

## Installation

**Prerequisites:**
- CloudNativePG (CNPG) operator must be installed for database
- Secrets must be created (see above)
- Update custom-values.yaml to use secrets and envFrom

### OCI (Recommended)

```bash
# Ensure custom-values.yaml uses secrets via envFrom
helm upgrade --install paperless-ngx oci://ghcr.io/gabe565/charts/paperless-ngx \
  -n paperless \
  --create-namespace \
  -f custom-values.yaml

# View default values
helm show values oci://ghcr.io/gabe565/charts/paperless-ngx > default-values.yaml
```

**Important:** Ensure your `custom-values.yaml` loads secrets via envFrom:
```yaml
envFrom:
  - secretRef:
      name: paperless-secrets

redis:
  auth:
    existingSecret: paperless-redis-credentials
    existingSecretPasswordKey: redis-password
```

### Traditional

```console
helm repo add gabe565 https://charts.gabe565.com
helm repo update
helm install paperless-ngx gabe565/paperless-ngx
helm show values k8s-charts/paperless-ngx > default-values.yaml
```

```console
helm upgrade --install -n paperless --create-namespace paperless-ngx gabe565/paperless-ngx -f custom-values.yaml
```

Create the first superuser:
```console
kubectl exec -it paperless-ngx-PODID -- su -s /bin/bash paperless -c "./manage.py createsuperuser"
```

## Uninstall

```
helm -n paperless uninstall paperless-ngx
# if not using longhorn
kubectl -n paperless delete -f paperless-media-pvc.yaml -f paperless-media-pv.yaml \
  -f paperless-psql-pvc.yaml -f paperless-psql-pv.yaml
```

## Backup / restore

See the [documentation](https://docs.paperless-ngx.com/administration/). Paperless-ngx has a built-in mechanism for backuping and restoring.