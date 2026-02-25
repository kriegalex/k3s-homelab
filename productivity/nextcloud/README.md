# Nextcloud Helm Chart

Target environment:

- Homelab small server
- <= 1TB stored data

## Persistent Storage

Create the PersistentVolumeClaim:

```bash
kubectl apply -f nextcloud-config-pvc.yaml
```

This creates a Longhorn-backed persistent volume with automatic replication and snapshot support.

## NFS User Data Storage

Apply NFS volume for Nextcloud user files:

```fish
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/productivity/nextcloud/nfs/nfs-nextcloud.yaml
```

See [Nextcloud NFS README](nfs/README.md) for details.

## Setup Secrets

⚠️ **IMPORTANT:** Never commit secrets to git. All password values must be stored in Kubernetes secrets.

### Create Secrets from Template

1. **Copy and edit the secrets template:**
```bash
cp secrets-template.yaml secrets.yaml
# Edit secrets.yaml and replace all CHANGE_ME_* placeholders with secure passwords
```

2. **Generate secure passwords:**
```bash
# Generate passwords (run this 4 times for each secret)
openssl rand -base64 32
```

3. **Apply the secrets:**
```bash
kubectl create namespace nextcloud
kubectl apply -f secrets.yaml
```

4. **Verify secrets were created:**
```bash
kubectl get secrets -n nextcloud
```

### Alternative: Create Secrets via Command Line

```bash
kubectl create namespace nextcloud

# Admin credentials
kubectl create secret generic nextcloud-admin-credentials \
  --from-literal=nextcloud-username='admin' \
  --from-literal=nextcloud-password="$(openssl rand -base64 32)" \
  --namespace=nextcloud

# Database credentials
kubectl create secret generic nextcloud-db-credentials \
  --from-literal=db-username='nextcloud' \
  --from-literal=db-password="$(openssl rand -base64 32)" \
  --namespace=nextcloud

# Redis credentials
kubectl create secret generic nextcloud-redis-credentials \
  --from-literal=redis-password="$(openssl rand -base64 32)" \
  --namespace=nextcloud

# Collabora credentials
kubectl create secret generic nextcloud-collabora-credentials \
  --from-literal=username='admin' \
  --from-literal=password="$(openssl rand -base64 32)" \
  --namespace=nextcloud
```

## Setup persistence (without longhorn)

On the control plane:
```console
kubectl apply -f nextcloud-config-pv.yaml -f nextcloud-config-pvc.yaml
kubectl apply -f nextcloud-psql-pv.yaml -f nextcloud-psql-pvc.yaml
kubectl apply -f nextcloud-redis-pv.yaml -f nextcloud-redis-pvc.yaml
```

### Setup permissions (worker nodes)

```
sudo mkdir -p /mnt/nextcloud/psql
sudo chown 1001:1001 /mnt/nextcloud/psql
sudo mkdir -p /mnt/nextcloud/redis
sudo chown 1001:1001 /mnt/nextcloud/redis
sudo mkdir -p /mnt/nextcloud/config
sudo chown www-data:www-data /mnt/nextcloud/config
```

### NFS

If you are creating a PV that uses NFS, it can be helpful to setup the share with the option `no_root_squash`, as Nextcloud will try to chown the data during initialization. If not done, it doesn't seem to break the installation.

## Install Nextcloud

**Prerequisites:**
- CloudNativePG (CNPG) operator must be installed
- Secrets must be created (see above)

```bash
helm repo add nextcloud https://nextcloud.github.io/helm/
helm repo update

# Install with secrets-based configuration
helm upgrade --install nextcloud nextcloud/nextcloud \
  --namespace nextcloud \
  --create-namespace \
  -f custom-values.yaml
```

**Important:** Ensure your `custom-values.yaml` references the secrets:
```yaml
nextcloud:
  existingSecret:
    enabled: true
    secretName: nextcloud-admin-credentials

externalDatabase:
  existingSecret:
    enabled: true
    secretName: nextcloud-db-credentials
    key: db-password

redis:
  auth:
    existingSecret: nextcloud-redis-credentials
    existingSecretPasswordKey: redis-password
```

## Database Backups (CloudNativePG)

The PostgreSQL cluster (`nextcloud-db`) is configured to automatically back up to S3-compatible storage:

- S3 endpoint: `http://10.0.0.7:8010`
- Bucket: `s3://nextcloud-backups/`
- Credentials secret: `nextcloud-s3-backup-credentials`
- Retention: 30 days

Before deploying, create the credentials secret:

```bash
kubectl create secret generic nextcloud-s3-backup-credentials -n nextcloud \
  --from-literal=ACCESS_KEY_ID=your_access_key \
  --from-literal=ACCESS_SECRET_KEY=your_secret_key
```

### Scheduled Backups

Apply the weekly scheduled backup (Mondays at 00:04):

```bash
kubectl apply -f nextcloud-scheduled-backup.yaml
kubectl get scheduledbackup -n nextcloud
```

### Manual Backup

```bash
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: nextcloud-db-backup-$(date +%Y%m%d-%H%M%S)
  namespace: nextcloud
spec:
  cluster:
    name: nextcloud-db
  method: barmanObjectStore
EOF

kubectl get backup -n nextcloud
kubectl describe backup <backup-name> -n nextcloud
```

## (optional) Backup and restore existing docker

### Backup

#### Postgres docker

PostgreSQL:
```console
docker exec -it nextcloud occ maintenance:mode --on
docker exec postgresql15 mkdir /backup
# backup inside the docker
docker exec postgresql15 pg_dump -U nextcloud -d nextcloud -f /backup/nextcloud_db_backup.sql
# extract the backup to the host
docker cp postgresql15:/backup/nextcloud_db_backup.sql /BACKUP_PATH/nextcloud-psql/
```

#### nextcloud/nextcloud docker

Nextcloud config:
```console
docker cp nextcloud:/config /BACKUP_PATH/nextcloud-config
```

Nextcloud data:
```console
docker cp nextcloud:/data /BACKUP_PATH/nextcloud-data
```

#### Kubernetes

```console
# occ must be launched as www-data
kubectl exec -it nextcloud-POD -c nextcloud -- su -s /bin/bash www-data -c "/var/www/html/occ maintenance:mode --on"
kubectl exec -it nextcloud-postgresql-0 -- pg_dump --clean --if-exists -U nextcloud -d nextcloud -f /tmp/nextcloud_db_backup.sql
kubectl cp nextcloud-postgresql-0:/tmp/nextcloud_db_backup.sql nextcloud_db_backup.sql
```

### Restore

To avoid issues, it is better to be restoring to the same nextcloud version, as well as the same docker with the same general configuration. For example, going from a docker "linuxserver/nextcloud" v25 to a helm chart using nextcloud/nextcloud v29 may give you a hard time. The inside of the config folder may not be arranged the same.

```console
kubectl cp nextcloud_db_backup.sql postgresql-0:/tmp/nextcloud_db_backup.sql
kubectl exec -it postgresql-0 -c postgresql -- psql -U postgres -d template1 -c "DROP DATABASE \"nextcloud\";"
kubectl exec -it postgresql-0 -c postgresql -- psql -U postgres -d template1 -c "CREATE DATABASE \"nextcloud\";"
kubectl exec -it postgresql-0 -c postgresql -- psql -U postgres -d template1 -c "ALTER DATABASE \"nextcloud\" OWNER TO nextcloud;"
kubectl exec -it postgresql-0 -c postgresql -- psql -U postgres -d template1 -c "GRANT ALL PRIVILEGES ON DATABASE \"nextcloud\" TO nextcloud;"
kubectl exec -it postgresql-0 -c postgresql -- psql -U nextcloud -d nextcloud -f /tmp/nextcloud_db_backup.sql
```

```console
kubectl cp /BACKUP_PATH/nextcloud-data <nextcloud_pod>:/var/www/html/data
kubectl cp /BACKUP_PATH/nextcloud-config <nextcloud_pod>:/var/www/html/config
```

#### DB hostname change

If the information about your DB changes, like the hostname or the DB password, changing them in the secret or in the helm chart is not enough.

You **MUST** also go to the config folder and modify accordingly in the `config.php` file.

#### Reindex files

If you start from scratch and manually copy the users data (/var/www/html/data/USER/files/MY_FILES), you must call `occ` to rescan the data.

```console
kubectl exec --tty --stdin nextcloud-POD -c nextcloud -- su -s /bin/bash www-data
./occ maintenance:mode --on
```

Perform now the copy operations.

When you are finished, you can launch the scan:

```console
kubectl exec --tty --stdin nextcloud-POD -c nextcloud -- su -s /bin/bash www-data
./occ maintenance:mode --off
./occ files:scan --all
```