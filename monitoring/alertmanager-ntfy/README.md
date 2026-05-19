# alertmanager-ntfy

A small Go bridge that accepts Alertmanager webhooks and posts formatted
messages to a [ntfy](https://ntfy.sh) topic. Bridges this cluster's
Alertmanager (configured in `monitoring/values.yaml`) to the in-cluster
ntfy server in [`../ntfy/`](../ntfy/).

Chart: [`oci://codeberg.org/wrenix/helm-charts/alertmanager-ntfy`](https://artifacthub.io/packages/helm/wrenix-helm-charts/alertmanager-ntfy) (v0.1.9, app [xenrox/ntfy-alertmanager](https://codeberg.org/xenrox/ntfy-alertmanager) v1.0.0).

> **Known issue — liveness/readiness probes (chart v0.1.9 bug):** The chart
> hardcodes `httpGet GET /` probes, but ntfy-alertmanager returns 405 for
> non-POST requests. Kubernetes kills the pod on every probe cycle. See
> [Post-install probe patch](#post-install-probe-patch) below — this must
> be re-applied after every `helm upgrade`.

## TL;DR

```bash
kubectl create namespace ntfy   # shared with the ntfy server; skip if already created
cp secrets-template.yaml helm-values-secret.yaml
# Edit helm-values-secret.yaml — fill in the publisher password
helm upgrade --install alertmanager-ntfy \
  oci://codeberg.org/wrenix/helm-charts/alertmanager-ntfy \
  --version 0.1.9 -n ntfy \
  -f values.yaml -f helm-values-secret.yaml
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
| `values.yaml`             | Helm overrides vs upstream defaults. Committed source of truth.                       |
| `secrets-template.yaml`   | Template for `helm-values-secret.yaml`. Committed.                                    |
| `helm-values-secret.yaml` | (gitignored) Real ntfy publisher credentials, layered on top of `values.yaml`.        |
| `helm-values.yaml`        | (gitignored) Snapshot of the live release values.                                     |

## Why this is configured the way it is

- **Credentials in a separate file.** The wrenix chart renders the
  bridge's config — including ntfy `user`/`password` — directly into a
  Helm-managed `Secret` from `.Values.ntfyAlertmanager.ntfy.{user,password}`.
  There is no `envFrom` or external-secret hook exposed, so the standard
  "point at a sealed Secret" pattern doesn't apply. We instead layer a
  second `-f helm-values-secret.yaml` (gitignored) that supplies only
  those two fields.
- **Topic URL uses the cluster-internal Service.** No reason for
  Alertmanager → bridge → ntfy traffic to leave the cluster and round-trip
  through Traefik/cert-manager.
- **Severity → priority mapping** mirrors the route tree in
  `monitoring/values.yaml`'s `alertmanager.config` (critical=5, warning=3,
  info=1). If you change one, change the other.

## Wiring Alertmanager

Add to `monitoring/values.yaml` under the existing `alertmanager:` block
(see `claude-docs/backup-strategy.md` §8.2 for the full route tree):

```yaml
alertmanager:
  config:
    route:
      receiver: ntfy
      group_by: [alertname, namespace]
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
  "annotations":{"summary":"smoke test — alertmanager-ntfy bridge"}
}]'
# Expect: a notification on the homelab-k3s ntfy topic within ~30 s.
```

If nothing arrives, check bridge logs (`kubectl -n ntfy logs deploy/alertmanager-ntfy`).
401s mean the publisher password is wrong; connection refused means the
ntfy service name/path is wrong; nothing logged means Alertmanager
didn't route to the bridge — re-check `monitoring/values.yaml`.

## Post-install probe patch

Chart v0.1.9 does not expose probe configuration in `.Values`. After every
`helm upgrade --install` run this patch to replace the broken `httpGet` probes
with TCP socket probes:

```bash
kubectl --context=default -n ntfy patch deployment alertmanager-ntfy \
  --type=json -p='[
    {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe",
     "value":{"tcpSocket":{"port":80},"initialDelaySeconds":5,"periodSeconds":10,"failureThreshold":3}},
    {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe",
     "value":{"tcpSocket":{"port":80},"initialDelaySeconds":5,"periodSeconds":5,"failureThreshold":3}}
  ]'
```

Remove this section once an upstream chart version exposes probe overrides.

## Upgrading

```bash
helm --kube-context=default -n ntfy upgrade alertmanager-ntfy \
  oci://codeberg.org/wrenix/helm-charts/alertmanager-ntfy \
  --version <new-version> \
  -f values.yaml -f helm-values-secret.yaml
# Then re-apply the probe patch above.
```
