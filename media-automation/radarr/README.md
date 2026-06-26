# Radarr

## Persistent Storage

Create the PersistentVolumeClaim:

```bash
kubectl apply -f radarr-pvc.yaml
```

This creates a Longhorn-backed persistent volume with automatic replication and snapshot support.

## NFS Media Libraries

Apply shared media NFS volumes before deploying Radarr:

```fish
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/media-automation/nfs/nfs-movies.yaml
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
  helm upgrade --install radarr alekc/radarr --namespace media --create-namespace -f values.yaml
  ```

### Default values

```bash
helm show values alekc/radarr > radarr-defaults.yaml
```