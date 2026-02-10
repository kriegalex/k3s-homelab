# Actual Budget

## Persistent Storage

Create the PersistentVolumeClaim:

```bash
kubectl apply -f actual-budget-pvc.yaml
```

This creates a Longhorn-backed persistent volume with automatic replication and snapshot support.

## Installation

```console
helm repo add k8s-charts https://kriegalex.github.io/k8s-charts/
helm repo update
helm show values k8s-charts/actual-budget > custom-values.yaml
```

> Adapt any needed values. Check [the original repository](https://github.com/kriegalex/k8s-charts/tree/main/charts/actual-budget) for more information.

```console
helm upgrade --install actual-budget k8s-charts/actual-budget -f custom-values.yaml
```

## Uninstall

```
helm uninstall actual-budget
kubectl delete -f actual_budget-data-pv.yaml -f actual_budget-data-pvc.yaml
```

## Backup / restore

See the [documentation](https://actualbudget.org/docs/backup-restore/backup). Actual Budget has a built-in mechanism for backuping and restoring the budgets.