# DeltaBadger

DCA (Dollar-Cost Averaging) bot for cryptocurrency, deployed on Kubernetes using Helm.

## Prerequisites

- Kubernetes cluster with storage provisioner
- Helm 3.x installed

## Secrets

The chart includes a built-in `secrets` section with placeholder values, so it works out of the box. However, for production use, it is recommended to manage secrets externally:

```bash
# Copy the template and fill in real values
cp secrets-template.yaml secrets.yaml
```

Generate secret values with:

```bash
openssl rand -hex 64  # SECRET_KEY_BASE
openssl rand -hex 64  # DEVISE_SECRET_KEY (not needed in v1.6.26+)
openssl rand -hex 32  # APP_ENCRYPTION_KEY (not needed in v1.6.26+)
```

Apply the secret:

```bash
kubectl create namespace deltabadger
kubectl apply -f secrets.yaml
```

Then disable the chart-managed secret and reference the external one in your values:

```yaml
secrets:
  secrets:
    enabled: false

controllers:
  deltabadger:
    containers:
      app:
        envFrom:
          - secretRef:
              name: deltabadger-secrets
```

> **Important:** Never commit `secrets.yaml` to version control. Only `secrets-template.yaml` should be tracked.

## Installation

```bash
helm repo add k8s-charts https://kriegalex.github.io/k8s-charts/
helm repo update
helm show values k8s-charts/deltabadger > values.yaml
```

> Adapt any needed values. Check [the original repository](https://github.com/kriegalex/k8s-charts/tree/main/charts/deltabadger) for more information.

```bash
helm upgrade --install deltabadger k8s-charts/deltabadger \
  --namespace deltabadger \
  --create-namespace \
  -f values.yaml
```

## Storage

The chart provisions a **50Gi Longhorn PVC** automatically (configured in `values.yaml`). No manual PV/PVC setup is needed.

## Verify

```bash
kubectl get pods -n deltabadger
kubectl get pvc -n deltabadger
kubectl logs -n deltabadger -l app.kubernetes.io/name=deltabadger
```

## Uninstall

```bash
helm uninstall deltabadger -n deltabadger
kubectl delete -f secrets.yaml
kubectl delete namespace deltabadger
```
