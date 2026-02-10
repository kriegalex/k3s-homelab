# Gitea

## Persistent Storage

Create the PersistentVolumeClaims:

```bash
kubectl apply -f gitea-redis-pvc.yaml
kubectl apply -f gitea-psql-pvc.yaml
```

This creates Longhorn-backed persistent volumes with automatic snapshot support. Note: These use `longhorn-single-replica` storage class since Redis and PostgreSQL handle their own data replication.

## Setup persistence

On the control plane:
```console
kubectl apply -f gitea-psql-pv.yaml -f gitea-psql-pvc.yaml
kubectl apply -f gitea-redis-pv.yaml -f gitea-redis-pvc.yaml
```

### Setup permissions (worker nodes)

```
sudo mkdir -p /mnt/gitea/psql
sudo chown 1001:1001 /mnt/gitea/psql
sudo mkdir -p /mnt/gitea/redis
sudo chown 1001:1001 /mnt/gitea/redis
```

## Setup secrets

```console
kubectl create secret generic gitea-admin-secret \
  --from-literal=username='your_username' \
  --from-literal=password='your_password' \
  --from-literal=email='your_email' \
  --from-literal=passwordMode='keepUpdated' \
  --namespace=default
```

## Install gitea

```console
helm repo add k8s-charts https://kriegalex.github.io/k8s-charts/
helm install gitea k8s-charts/gitea -f custom-values.yaml
```

## (optional) Backup and restore existing docker 

### Backup

PostgreSQL:
```console
docker exec postgresql15 mkdir /backup
# backup inside the docker
docker exec postgresql15 pg_dump --clean --if-exists -U gitea -d giteadb -f /backup/gitea_db_backup.sql
# extract the backup to the host
docker cp postgresql15:/backup/gitea_db_backup.sql /BACKUP_PATH/gitea-psql/
```

### Restore

```console
kubectl cp gitea_db_backup.sql gitea-postgresql-0:/tmp/gitea_db_backup.sql
kubectl exec -it gitea-postgresql-0 -c postgresql -- psql -U gitea -d gitea -f /tmp/gitea_db_backup.sql
```

> Tip : you can use `initPreScript` to buy you some time before Gitea starts up.