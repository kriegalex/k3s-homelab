# alertmanager-ntfy

A small Go bridge that accepts Alertmanager webhooks and posts formatted
messages to a [ntfy](https://ntfy.sh) topic. Bridges this cluster's
Alertmanager (configured in `monitoring/values.yaml`) to the in-cluster
ntfy server in [`../ntfy/`](../ntfy/).

Chart: [`k8s-charts/alertmanager-ntfy`](https://github.com/kriegalex/k8s-charts/tree/main/charts/alertmanager-ntfy)
v0.3.0 — an AGPL-3.0 fork of the upstream
[`xenrox/ntfy-alertmanager`](https://codeberg.org/xenrox/ntfy-alertmanager)
`contrib/charts/alertmanager-ntfy` chart, extended to expose the full
set of scfg config knobs (`alert-mode`, `ntfy.template-path`,
`ntfy.generator-url-label`, `resolved.update-notification`, `cache{}`,
`alertmanager{}` silence block). App: [xenrox/ntfy-alertmanager](https://codeberg.org/xenrox/ntfy-alertmanager) v1.0.0.

## TL;DR

```bash
helm repo add k8s-charts https://kriegalex.github.io/k8s-charts/   # one-time
helm repo update
kubectl create namespace ntfy   # shared with the ntfy server; skip if already created
# Create the alertmanager-ntfy-config Secret (full rendered bridge config +
# credentials) — generation procedure in secrets-template.yaml
helm upgrade --install alertmanager-ntfy k8s-charts/alertmanager-ntfy \
  --version 0.3.0 -n ntfy -f values.yaml
```

Then point Alertmanager at it — see "Wiring Alertmanager" below.

## Prerequisites

- The ntfy server in [`../ntfy/`](../ntfy/) is deployed and has a user
  named `homelab-publisher` with read-write access to `homelab-*` topics
  (see that folder's README §3).
- kube-prometheus-stack is running in `monitoring/`. The Alertmanager
  CR's `alertmanager.config` block (in `monitoring/values.yaml`) routes
  alerts to this bridge — see the §8.2 worked example in
  `claude-docs/backup-strategy.md`.

## Files in this folder

| File                      | Purpose                                                                               |
| ------------------------- | ------------------------------------------------------------------------------------- |
| `values.yaml`             | Helm overrides vs upstream defaults. Committed source of truth for the config *shape* (credentials excluded). |
| `secrets-template.yaml`   | Procedure + credential template for the manually created `alertmanager-ntfy-config` Secret. Committed. |
| `helm-values.yaml`        | (gitignored) Snapshot of the live release values.                                     |

## Why this is configured the way it is

- **Credentials in a manually created Secret (chart ≥ 0.3.0).** The chart's
  `ntfyAlertmanager.existingSecret` points the deployment at the
  `alertmanager-ntfy-config` Secret, which holds the complete rendered scfg
  config (including the ntfy publisher credentials) plus `template.tmpl`.
  The chart then renders no Secret of its own and ignores the rest of the
  `ntfyAlertmanager.*` block — that block stays committed in `values.yaml`
  as the source for regenerating the config (procedure in
  `secrets-template.yaml`). This replaced the old gitignored
  `helm-values-secret.yaml` second `-f` layering.
- **Topic URL uses the cluster-internal Service.** No reason for
  Alertmanager → bridge → ntfy traffic to leave the cluster and round-trip
  through Traefik/cert-manager.
- **Severity → priority mapping** mirrors the route tree in
  `monitoring/values.yaml`'s `alertmanager.config` (critical=5, warning=3,
  info=1). If you change one, change the other.
- **`alertMode: multi` + custom template + cache.** The upstream binary's
  default body formatter dumps every label and annotation — 90% noise
  on a phone. We render only the `summary` and `description` annotations,
  and multi mode batches Alertmanager groups into a single ntfy push
  (essential for storms — many Longhorn volumes failing at once become
  one notification listing all of them, not N pushes). The cache key
  is the group fingerprint, so the same group of failures doesn't
  re-publish on every Alertmanager re-evaluation.

## Wiring Alertmanager

Add to `monitoring/values.yaml` under the existing `alertmanager:` block
(see `claude-docs/backup-strategy.md` §8.2 for the full route tree):

```yaml
alertmanager:
  config:
    route:
      receiver: ntfy
      group_by: [alertname, namespace]   # multi alertMode batches storms into one push per group
      routes:
        - matchers: [alertname = "Watchdog"]
          receiver: "null"
        - matchers: [severity = "info"]
          receiver: "null"
    receivers:
      - name: "null"
      - name: ntfy
        webhook_configs:
          - url: http://alertmanager-ntfy.ntfy.svc.cluster.local/
            send_resolved: true
```

Then re-apply the monitoring stack:

```bash
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring -f monitoring/values.yaml \
  -f monitoring/grafana-dashboards.yaml --version 63.1.0
```

## Verifying

```bash
# Bridge running
kubectl -n ntfy get deploy,svc,pods -l app.kubernetes.io/name=alertmanager-ntfy

# Synthetic alert end-to-end test (see backup-strategy.md §8.2 step 2.4)
kubectl -n monitoring port-forward svc/alertmanager-operated 9093
curl -s -XPOST localhost:9093/api/v2/alerts -H 'Content-Type: application/json' -d '[{
  "labels":{"alertname":"BridgeSmokeTest","severity":"warning","namespace":"monitoring"},
  "annotations":{"summary":"smoke test — alertmanager-ntfy bridge","description":"This is the description body that lands on your phone."}
}]'
# Expect: a notification on the homelab-k3s ntfy topic within ~30 s.
# Title: [FIRING] BridgeSmokeTest monitoring
# Body:  **smoke test — alertmanager-ntfy bridge**
#        This is the description body that lands on your phone.
# Plus a tappable "View in Prometheus" action button.
```

If nothing arrives, check bridge logs (`kubectl -n ntfy logs deploy/alertmanager-ntfy`).
401s mean the publisher password is wrong; connection refused means the
ntfy service name/path is wrong; nothing logged means Alertmanager
didn't route to the bridge — re-check `monitoring/values.yaml`.

## Upgrading

```bash
helm repo update k8s-charts
helm --kube-context=default -n ntfy upgrade alertmanager-ntfy k8s-charts/alertmanager-ntfy \
  --version <new-version> \
  -f values.yaml
```

No post-install patches required — `/health` probes and full scfg
field coverage are baked into the chart.
