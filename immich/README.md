# Immich

## NFS Photo Storage

Apply NFS volumes for Immich photo and video storage:

```fish
# Immich's own storage (read-write)
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/immich/nfs/nfs-immich.yaml

# Nextcloud photos (read-only) - optional, for importing from Nextcloud
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/immich/nfs/nfs-nextcloud-ro.yaml
```

See [Immich NFS README](nfs/README.md) for details.

## Setup Secrets

⚠️ **IMPORTANT:** Database password must be stored in a Kubernetes secret.

### Create Secrets from Template

1. **Copy and edit the secrets template:**
```bash
cp secrets-template.yaml secrets.yaml
# Edit secrets.yaml and replace CHANGE_ME_DB_PASSWORD
```

2. **Generate secure password:**
```bash
openssl rand -base64 32
```

3. **Apply the secret:**
```bash
kubectl create namespace immich
kubectl apply -f secrets.yaml
```

### Alternative: Create Secret via Command Line

```bash
kubectl create namespace immich

DB_PASSWORD="$(openssl rand -base64 32)"

kubectl create secret generic immich-db-credentials \
  --from-literal=password="${DB_PASSWORD}" \
  --from-literal=DB_PASSWORD="${DB_PASSWORD}" \
  --namespace=immich
```

## Installation

**Prerequisites:**
- CloudNativePG (CNPG) operator must be installed
- Database credentials secret must be created (see above)
- Update values.yaml to use secrets via envFrom

```bash
helm repo add immich-charts https://immich-app.github.io/immich-charts
helm repo update

# View default values
helm show values immich-charts/immich > values.yaml
```

> Adapt any needed values. Check [the original repository](https://github.com/immich-app/immich-charts) for more information.

**Important:** Ensure your `values.yaml` uses secrets:
```yaml
controllers:
  main:
    containers:
      main:
        env:
          DB_HOSTNAME: immich-db-rw
          DB_DATABASE_NAME: immich
          DB_USERNAME: immich
        envFrom:
          - secretRef:
              name: immich-db-credentials
```

```bash
helm upgrade --install immich immich-charts/immich \
  -n immich \
  --create-namespace \
  -f values.yaml
```

## Uninstall

```
helm uninstall immich
kubectl delete -f immich-ml-data-pvc.yaml -f immich-ml-data-pv.yaml \
  -f immich-psql-data-pv.yaml
kubectl delete pvc data-immich-postgresql-0
```

## Database Backups (CloudNativePG)

The PostgreSQL cluster (`immich-db`) is configured to automatically back up to S3-compatible storage via the `barman-cloud.cloudnative-pg.io` plugin (in-tree `barmanObjectStore` is removed as of operator 1.31). The S3 target is the `ObjectStore` CR in [`immich-objectstore.yaml`](immich-objectstore.yaml):

- S3 endpoint: `http://10.0.0.7:8010`
- Bucket: `s3://immich-backups/`
- Credentials secret: `immich-s3-backup-credentials`
- Retention: 30 days (`ObjectStore.spec.retentionPolicy`)

Before deploying, create the credentials secret:

```bash
kubectl create secret generic immich-s3-backup-credentials -n immich \
  --from-literal=ACCESS_KEY_ID=your_access_key \
  --from-literal=ACCESS_SECRET_KEY=your_secret_key
```

Apply the ObjectStore before (or alongside) the cluster:

```bash
kubectl apply -f immich-objectstore.yaml
```

### Scheduled Backups

Apply the weekly scheduled backup (Mondays at 00:04):

```bash
kubectl apply -f immich-scheduled-backup.yml
kubectl get scheduledbackup -n immich
```

### Manual Backup

```bash
kubectl cnpg backup immich-db -n immich \
  --method=plugin --plugin-name=barman-cloud.cloudnative-pg.io

kubectl get backups.postgresql.cnpg.io -n immich
kubectl describe backups.postgresql.cnpg.io <backup-name> -n immich
```

### Backup Health

```bash
kubectl get objectstore immich-backup-store -n immich \
  -o jsonpath='{.status.serverRecoveryWindow}'
kubectl cnpg status immich-db -n immich
```

> **Note:** Immich uses a custom PostgreSQL image (`cloudnative-vectorchord`) with special extensions. CNPG bootstrap recovery is **not supported** for restore — use the `pg_dumpall` method below instead. The plugin-managed S3 backup still provides WAL archiving and point-in-time protection.

## Backup & Restore

Always refer to the instructions here as a baseline:

- https://immich.app/docs/administration/backup-and-restore

### Note on migration

- https://github.com/immich-app/immich/discussions/9060

Immich currently requires `pgdump_all` instead of `pg_dump` for the migration process to work. Unlike paperless, nextcloud or gitea, immich cannot use the Cluster import bootstrap functionality. For now, a manual backup and a manual restore is the easiest and quickest option. Simply set immich to skip the database migrations when doing migrations (see ansible variables).

### Manual backup

```bash
# change the namespace to suit your needs
kubectl -n immich exec immich-db-1 -c postgres -- sh -c 'pg_dumpall --clean --if-exists --username=postgres | gzip > "/var/lib/postgresql/data/dump.sql.gz"'
kubectl -n immich cp -c postgres immich-db-1:/var/lib/postgresql/data/dump.sql.gz ./dump.sql.gz 
```

### Manual restore

```bash
gunzip < "./dump.sql.gz" | sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" > dump.sql
# change the namespace to suit your needs
kubectl -n immich cp -c postgres ./dump.sql immich-db-1:/var/lib/postgresql/data/dump.sql
# avoid passwords with "$" if possible
kubectl -n immich exec immich-db-1 -c postgres -- sh -c 'PGPASSWORD="YOUR_PASSWORD" psql --dbname=postgres --username=immich --host=localhost -f /var/lib/postgresql/data/dump.sql'
kubectl -n immich exec immich-db-1 -c postgres -- rm /var/lib/postgresql/data/dump.sql
```

### Migration to immich v1.133.0

Link to [manual migration](https://immich.app/docs/administration/postgres-standalone/#migrating-to-vectorchord).

- Backup data and connect to the DB:
  ```bash
  kubectl -n immich scale deployment immich-server immich-machine-learning --replicas 0
  kubectl -n immich exec immich-db-1 -c postgres -- sh -c 'pg_dumpall --clean --if-exists --username=postgres | gzip > "/var/lib/postgresql/data/dump.sql.gz"'
  kubectl -n immich cp -c postgres immich-db-1:/var/lib/postgresql/data/dump.sql.gz ./dump.sql.gz
  # follow steps from manual migration, but with kubectl in the correct pod
  kubectl -n immich exec -it immich-db-1 -c postgres -- bash -c 'psql --dbname=immich'
  ````
- Use this SELECT command:
  ```sql
  # copy this SELECT command
  SELECT atttypmod as dimsize
      FROM pg_attribute f
      JOIN pg_class c ON c.oid = f.attrelid
      WHERE c.relkind = 'r'::char
      AND f.attnum > 0
      AND c.relname = 'smart_search'::text
      AND f.attname = 'embedding'::text;
  ```
- Note the result:
  ```text
  dimsize
  ---------
      512
  (1 row)
  ```
- Use these SQL commands:
  ```sql
  DROP INDEX IF EXISTS clip_index;
  DROP INDEX IF EXISTS face_index;
  ALTER TABLE smart_search ALTER COLUMN embedding SET DATA TYPE real[];
  ALTER TABLE face_search ALTER COLUMN embedding SET DATA TYPE real[];
  ```

- Update the image to start using vectorchord:
  ```bash
  # or use the kubectl patch/edit cmd for the imageName and shared_preload_libraries parameters
  kubectl -n immich apply -f cnpg-cluster_migration.yaml
  ```

- Connect to the DB and update it for vectorchord (remember the value from 1st SELECT above):
  ```bash
  kubectl -n immich exec -it immich-db-1 -c postgres -- bash -c 'psql --dbname=immich'
  ```

  ```sql
  CREATE EXTENSION IF NOT EXISTS vchord CASCADE;
  ALTER TABLE smart_search ALTER COLUMN embedding SET DATA TYPE vector(<number>);
  ALTER TABLE face_search ALTER COLUMN embedding SET DATA TYPE vector(512);
  ```

- Update the immich deployment to version 1.133.0
  ```bash
  # double check the image tag is set to 1.133.0
  helm -n immich upgrade immich immich/immich -f values.yaml
  ```

- If the logs complain about a version 2.31 and 2.36 mismatch:
  ```bash
  kubectl -n immich exec -it immich-db-1 -c postgres -- bash -c 'psql --dbname=immich'
  ```
  
  ```sql
  ALTER DATABASE immich REFRESH COLLATION VERSION;
  REINDEX DATABASE immich;
  ```

## "error: invalid command \N"

If you try to use a regular centralized PostgreSQL database with immich, it won't work. A popular example of that would be the bitnami image of PostgreSQL. 

Immich however uses the `tensorchord/pgvecto-rs` image for PSQL. It has some special extensions that make it incompatible with regular versions of PostgreSQL servers.