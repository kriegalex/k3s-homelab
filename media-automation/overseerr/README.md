# Overseerr

## Persistent Storage

Create the PersistentVolumeClaim:

```bash
kubectl apply -f overseerr-config-pvc.yaml
```

This creates a Longhorn-backed persistent volume with automatic replication and snapshot support.

## Add repository

```
helm repo add k8s-at-home https://k8s-at-home.com/charts/
helm repo update
```

## Install chart

```
helm -n media --create-namespace upgrade --install overseerr k8s-at-home/overseerr -f custom-values.yaml
```

### Default values

```bash
helm show values k8s-at-home/overseerr > overseerr-defaults.yaml
```