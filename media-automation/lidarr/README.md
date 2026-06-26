# Lidarr

## Persistent Storage

Create the PersistentVolumeClaim:

```bash
kubectl apply -f lidarr-config-pvc.yaml
```

This creates a Longhorn-backed persistent volume with automatic replication and snapshot support.

## NFS Media Libraries

Apply shared media NFS volumes before deploying Lidarr:

```fish
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/media-automation/nfs/nfs-music.yaml
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/media-automation/qbittorrent/nfs/nfs-torrent.yaml
```

See [Media NFS Guide](../nfs/README.md) for details.

## Add repository

```bash
helm repo add k8s-home-lab https://k8s-home-lab.github.io/helm-charts/
helm repo update
```

## Install chart

### Without longhorn

- Setup permissions on worker nodes:

  ```bash
  sudo mkdir -p /mnt/lidarr/
  sudo chown 1000:1000 /mnt/lidarr/
  ```

- Create PV and PVC:

  ```bash
  kubectl apply -f lidarr-config-pv.yaml
  ```

### With longhorn

- Create PVC through longhorn class name:

  ```bash
  kubectl apply -f lidarr-config-longhorn.yaml
  ```

### NFS

```bash
kubectl apply -f ../../storage/nfs-shares/nfs-music.yaml
```

### Installation

Install:
```bash
helm -n media upgrade --install lidarr k8s-home-lab/lidarr -f values.yaml
```
