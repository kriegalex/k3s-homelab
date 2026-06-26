# Sonarr

## Persistent Storage

Create the PersistentVolumeClaims:

```bash
kubectl apply -f sonarr-tv-pvc.yaml
kubectl apply -f sonarr-anime-pvc.yaml
```

This creates Longhorn-backed persistent volumes with automatic replication and snapshot support.

## NFS Media Libraries

Apply shared media NFS volumes before deploying Sonarr:

```fish
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/media-automation/nfs/nfs-tv.yaml
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/media-automation/nfs/nfs-anime.yaml
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/media-automation/qbittorrent/nfs/nfs-torrent.yaml
```

See [Media NFS Guide](../nfs/README.md) for details.

## Add repository

```bash
helm repo add alekc https://charts.alekc.dev
helm repo update
```

## Install chart

Then install the helm chart:

  ```bash
  # If the namespace doens't exist
  helm upgrade --install sonarr-tv alekc/sonarr --namespace media --create-namespace -f values-tv.yaml
  ```

  ```bash
  # If the namespace doens't exist
  helm upgrade --install sonarr-anime alekc/sonarr --namespace media --create-namespace -f values-anime.yaml
  ```

### Default values

```bash
helm show values alekc/sonarr > sonarr-defaults.yaml
```