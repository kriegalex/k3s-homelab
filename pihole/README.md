# Pi-hole

## Persistence

I'm using longhorn to get a redundant PersistentVolume automatically.

```
kubectl apply -f -f pihole-config-pvc.yaml
```

## Add repository

```
helm repo add mojo2600 https://mojo2600.github.io/pihole-kubernetes/
helm repo update
```

## Custom values

```console
helm show values mojo2600/pihole > custom-values.yaml
```

## Install chart

```
helm upgrade --install pihole mojo2600/pihole -f custom-values.yaml
```

