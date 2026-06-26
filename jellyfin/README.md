# Jellyfin

## Setup persistence

On the control plane:
```console
kubectl apply -f jellyfin-config-pvc.yaml
```

## Jellyfin installation

1. Add the Jellyfin helm repo:
```console
helm repo add k8s-charts https://kriegalex.github.io/k8s-charts/
```

2. Inspect and modify the default values:
```console
helm show values k8s-charts/jellyfin > values.yaml
```

You can check an [example here](./values.yaml).

3. Install
```console
helm upgrade --install jellyfin k8s-charts/jellyfin -f values.yaml
```