# Sonarr

## Persistent Storage

Create the PersistentVolumeClaims:

```bash
kubectl apply -f sonarr-tv-pvc.yaml
kubectl apply -f sonarr-anime-pvc.yaml
```

This creates Longhorn-backed persistent volumes with automatic replication and snapshot support.

## Add repository

```bash
helm repo add alekc https://charts.alekc.dev
helm repo update
```

## Install chart

Then install the helm chart:

  ```bash
  # If the namespace doens't exist
  helm upgrade --install sonarr-tv alekc/sonarr --namespace media --create-namespace -f tv-custom-values.yaml
  ```

  ```bash
  # If the namespace doens't exist
  helm upgrade --install sonarr-anime alekc/sonarr --namespace media --create-namespace -f anime-custom-values.yaml
  ```

### Default values

```bash
helm show values alekc/sonarr > sonarr-defaults.yaml
```