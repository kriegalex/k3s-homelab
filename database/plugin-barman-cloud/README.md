# plugin-barman-cloud

CNPG-I backup plugin for CloudNativePG — replaces the deprecated in-tree
`.spec.backup.barmanObjectStore` support (removed in operator 1.31.0). It runs as its
own operator in `cnpg-system`, injects a `plugin-barman-cloud` sidecar into every
postgres instance pod, and performs WAL archiving, base backups, and restores against
the object stores declared via the `ObjectStore` CRD (`barmancloud.cnpg.io/v1`).

- Docs: <https://cloudnative-pg.io/plugin-barman-cloud/docs/intro/>
- Migration guide: <https://cloudnative-pg.io/plugin-barman-cloud/docs/migration/>

## Requirements

- CloudNativePG ≥ 1.27 (installed here: see `../cloudnative-pg/`)
- cert-manager (issues the plugin's gRPC TLS certificates)

## Install / upgrade

```bash
helm repo update cnpg

helm diff upgrade plugin-barman-cloud cnpg/plugin-barman-cloud \
  -n cnpg-system --version 0.7.0 \
  -f database/plugin-barman-cloud/values.yaml --allow-unreleased

helm upgrade --install plugin-barman-cloud cnpg/plugin-barman-cloud \
  -n cnpg-system --version 0.7.0 \
  -f database/plugin-barman-cloud/values.yaml
```

Pinned: chart **0.7.0** = plugin **v0.13.0**.

## Verify

```bash
kubectl -n cnpg-system rollout status deploy/plugin-barman-cloud
kubectl get crd objectstores.barmancloud.cnpg.io
kubectl -n cnpg-system get certificate    # barman-cloud-client / barman-cloud-server Ready
```

## Usage

Each CNPG cluster references an `ObjectStore` CR living in its own namespace
(committed beside the cluster manifest, e.g. `productivity/n8n/*-objectstore.yaml`)
through `.spec.plugins[0].parameters.barmanObjectName`. Backup health is read from
`ObjectStore .status.serverRecoveryWindow` and the
`barman_cloud_cloudnative_pg_io_*` Prometheus metrics — **not** from the Cluster's
`.status.lastSuccessfulBackup` (in-tree only, frozen after migration).

> **Warning**: uninstalling the chart leaves the `ObjectStore` CRD in place. Deleting
> the CRD deletes every ObjectStore and the backup configuration it holds.
