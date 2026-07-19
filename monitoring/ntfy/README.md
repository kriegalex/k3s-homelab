# ntfy

[ntfy](https://ntfy.sh) is a self-hosted pub/sub push-notification service.
This deployment is the central inbox for homelab alarms: Alertmanager (via
the [`alertmanager-ntfy`](../alertmanager-ntfy/) bridge), Unraid notification
agent, and QNAP (via SMTP bridge — see backup-strategy.md §8.3).

Chart: [`oci://codeberg.org/wrenix/helm-charts/ntfy`](https://artifacthub.io/packages/helm/wrenix-helm-charts/ntfy) (v0.5.15, app v2.22.0).

## TL;DR

```bash
kubectl create namespace ntfy
# 1. Edit secrets-template.yaml (placeholders → real passwords),
#    save as ntfy-secrets.yaml (gitignored), then apply:
kubectl apply -f ntfy-secrets.yaml
# 2. Create the web-push contact e-mail Secret — see "Web-push contact
#    e-mail" under Configuration below.
kubectl -n ntfy create secret generic ntfy-web-push-email \
  --from-literal=NTFY_WEB_PUSH_EMAIL_ADDRESS='<your-admin-email>'
helm upgrade --install ntfy oci://codeberg.org/wrenix/helm-charts/ntfy \
  --version 0.5.15 -n ntfy -f values.yaml
# After the pod is Ready, bootstrap users (see §3).
```

## Prerequisites

- k3s cluster with Longhorn (PVC) + Traefik (Ingress) + cert-manager
  (`letsencrypt-prod` ClusterIssuer) — same as every other web app in this repo.
- A DNS record for `ntfy.<your-domain>` pointing at the Traefik LB IP
  (`10.0.0.20` in this cluster).
- kube-prometheus-stack already installed in `monitoring/` (the
  ServiceMonitor enabled in `values.yaml` requires it).

## Configuration

### Topic layout

One topic per source so each can be muted/unsubscribed independently:

| Topic              | Producer                                    |
| ------------------ | ------------------------------------------- |
| `homelab-k3s`      | `alertmanager-ntfy` bridge → Alertmanager   |
| `homelab-unraid`   | Unraid Notification Agent (Custom/Webhook)  |
| `homelab-qnap`     | QNAP → mailrise SMTP bridge → ntfy          |

Subscribe to all three from the ntfy Android/iOS app.

### Web-push contact e-mail (`ntfy-web-push-email` Secret)

`values.yaml` keeps a placeholder `webPush.emailAddress` (the address is PII).
The real one is injected as an env var from a manually created Secret — ntfy
env vars override `server.yml`, so the placeholder never reaches clients:

```bash
kubectl -n ntfy create secret generic ntfy-web-push-email \
  --from-literal=NTFY_WEB_PUSH_EMAIL_ADDRESS='<your-admin-email>'   # shown in VAPID contact info
```

(Real domain/baseURL/ingress hosts are committed directly in `values.yaml`
since the 2026-06-26 source-of-truth inversion — no override layer needed.)

### Files in this folder

| File                       | Purpose                                                              |
| -------------------------- | -------------------------------------------------------------------- |
| `values.yaml`              | Helm overrides vs upstream defaults. Committed source of truth.      |
| `secrets-template.yaml`    | Placeholder Secrets: bootstrap credentials + web-push e-mail. Committed. |
| `ntfy-secrets.yaml`        | (gitignored) Real bootstrap credentials.                             |
| `helm-values.yaml`         | (gitignored) Snapshot of the live release values.                    |

### Why these overrides

See header comment in `values.yaml`; the file only lists the keys we change
from the chart defaults. Notable choices:

- **`auth.defaultAccess: deny-all`** — homelab inbox, not a public service.
- **`webPush.keys.create: true`** — chart generates VAPID keys once and
  stores them in a Secret, so mobile push works out of the box.
- **`persistence.enabled: true` (longhorn, 2Gi)** — needed for `user.db`,
  `cache.db`, attachments, and `webpush.db` to survive pod restarts.
- **`prometheus.servicemonitor.enabled: true` + `labels.release: prometheus`** —
  exposes ntfy's `/metrics` endpoint to kube-prometheus-stack. The
  `release: prometheus` label is mandatory or Prometheus silently
  ignores the ServiceMonitor (see incident notes).

## 3. Create users

`user.db` is created empty on first start (the chart sets
`auth.defaultAccess: deny-all` so the API is locked down immediately).
Seed it once:

```bash
# 1. Apply the secret with admin + publisher passwords (placeholders edited)
kubectl apply -f ntfy-secrets.yaml

# 2. Read passwords back so we don't paste them on the CLI
ADMIN_PW=$(kubectl -n ntfy get secret ntfy-bootstrap -o jsonpath='{.data.admin-password}' | base64 -d)
PUB_PW=$(kubectl -n ntfy get secret ntfy-bootstrap -o jsonpath='{.data.publisher-password}' | base64 -d)

# 3. Create the two users + scope publisher to homelab-* topics
kubectl -n ntfy exec deploy/ntfy -- sh -c "NTFY_PASSWORD='$ADMIN_PW' ntfy user add --role=admin admin"
kubectl -n ntfy exec deploy/ntfy -- sh -c "NTFY_PASSWORD='$PUB_PW' ntfy user add homelab-publisher"
kubectl -n ntfy exec deploy/ntfy -- ntfy access homelab-publisher 'homelab-*' rw

# 4. (Optional) Issue a token for the publisher — easier to rotate than the password
kubectl -n ntfy exec deploy/ntfy -- ntfy token add homelab-publisher
# → tk_xxxxxxxxxxxxxxxx   (copy this into alertmanager-ntfy/ntfy-secrets.yaml)
```

To add personal subscriber accounts later, repeat `ntfy user add` and grant
`ro` on whichever topic prefix that user should see.

## Upgrading

```bash
helm -n ntfy upgrade ntfy oci://codeberg.org/wrenix/helm-charts/ntfy \
  --version <new-version> -f values.yaml
```

Bump the version pin in `values.yaml`'s header comment and in this README's
TL;DR. The chart respects PVC retention, so user/cache data survives upgrades.

## Verifying

```bash
# Pod
kubectl -n ntfy get pods,svc,ingress

# Metrics scrape (release: prometheus label required)
kubectl -n monitoring port-forward svc/prometheus-operated 9090
# → http://localhost:9090 → search ntfy_messages_published_total

# Send a test message as the publisher — password auth:
curl -u "homelab-publisher:<password>" \
  -d "hello from homelab" https://ntfy.homelab.example.com/homelab-k3s

# Token auth (ntfy token add output — use Bearer header, not basic auth):
curl -H "Authorization: Bearer tk_xxxxxxxxxxxxxxxxxx" \
  -d "hello from homelab" https://ntfy.homelab.example.com/homelab-k3s

# If the cert-manager certificate is not yet ready (e.g. right after install),
# add -k to skip TLS verification — remove it once the cert is issued:
curl -k -H "Authorization: Bearer tk_xxxxxxxxxxxxxxxxxx" \
  -d "hello from homelab" https://ntfy.homelab.example.com/homelab-k3s
```

## Related

- `monitoring/alertmanager-ntfy/` — Alertmanager → ntfy bridge.
- `claude-docs/backup-strategy.md` §8.2–8.3 — full alerting design,
  including Unraid agent setup and the QNAP SMTP bridge.
