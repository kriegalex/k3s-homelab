# Deploy Satisfactory Server

## Add Helm Repository

```bash
helm repo add naj98 https://98jan.github.io/helm-charts/
helm repo update
```

## Install Server using Helm

```bash
helm upgrade --install satisfactory-server naj98/satisfactory \
  --namespace game-servers \
  --create-namespace \
  -f custom-values.yaml
```
