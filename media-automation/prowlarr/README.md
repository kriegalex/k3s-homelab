# Prowlarr

## Persistent Storage

Create the PersistentVolumeClaim:

```bash
kubectl apply -f prowlarr-pvc.yaml
```

This creates a Longhorn-backed persistent volume with automatic replication and snapshot support.

## Add repository

```
helm repo add alekc https://charts.alekc.dev
helm repo update
```

## Install chart

```
helm upgrade --install --namespace media --create-namespace prowlarr alekc/prowlarr -f values.yaml
```

### Default values

```bash
helm show values alekc/prowlarr > prowlarr-defaults.yaml
```