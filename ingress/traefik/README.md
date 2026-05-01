# Traefik

Traefik v3 is the only ingress controller in this cluster. It replaced
ingress-nginx in April 2026; see `~/workspace/traefik-migration/MIGRATION_GUIDE.md`
for the migration playbook.

| Property | Value |
| --- | --- |
| Helm chart | `traefik/traefik` |
| Chart version | `traefik-39.0.8` (appVersion `v3.6.13`) |
| Namespace | `traefik` |
| Service type | `LoadBalancer` (MetalLB) |
| External IP | `10.0.0.20` |
| IngressClass | `traefik` (NOT cluster default — every Ingress sets `ingressClassName: traefik` explicitly) |
| Dashboard | `http://traefik.k3s.home` (IngressRoute, no auth — internal-only via DNS) |

## Files

```
ingress/traefik/
├── README.md                     # this file
├── values.yaml                   # Helm values (committed)
├── ingressroute-dashboard.yaml   # IngressRoute serving the Traefik dashboard
└── middlewares/                  # cluster-wide Middleware/ServersTransport CRDs
    ├── README.md
    ├── nextcloud.yaml            # 4 mws: well-known-dav, well-known-rewrite, security-headers, cors
    ├── collabora-timeout.yaml    # ServersTransport: 600s timeouts for Collabora
    ├── paperless-body-64m.yaml   # 64 MiB request body buffer for Paperless uploads
    └── redirect-https.yaml       # generic HTTP→HTTPS redirect (used by deltabadger, n8n)
```

The `_live/` directory is a temporary `kubectl`/`helm get values` dump used
during reconciliation work; it's gitignored (see top-level `.gitignore`).

## Add repository

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
```

## Install / upgrade

The cluster has a single Traefik release; bootstrap order is **MetalLB →
cert-manager → Traefik** (apps come after).

```bash
# Initial install
helm upgrade --install traefik traefik/traefik \
  --namespace traefik --create-namespace \
  --version 39.0.8 \
  -f values.yaml

# Apply the dashboard route + middlewares
kubectl apply -f ingressroute-dashboard.yaml
kubectl apply -f middlewares/
```

Subsequent upgrades: bump `--version` and re-run `helm upgrade --install`.

## Per-Ingress middleware references

Apps reference middlewares via the standard annotation:

```yaml
metadata:
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: "<namespace>-<name>@kubernetescrd[,<namespace>-<name>@kubernetescrd]"
```

Live consumers today:

| Ingress | Middlewares used |
| --- | --- |
| `deltabadger/deltabadger` | `traefik-redirect-https` |
| `n8n/n8n` | `traefik-redirect-https` |
| `nextcloud/nextcloud` | `nextcloud-wellknown-dav`, `nextcloud-wellknown-rewrite`, `nextcloud-security-headers`, `nextcloud-cors` |
| `paperless/paperless-ngx` | `paperless-body-limit-64m` |

`allowCrossNamespace: false` is set in `values.yaml` — namespace prefixes are mandatory.

## TLS

cert-manager (separate install in `../cert-manager/`) issues per-Ingress certs.
Traefik consumes them via the standard `tls.secretName` field on the Ingress
resource — no Traefik-side configuration needed.

## Default values

```bash
helm show values traefik/traefik --version 39.0.8 > traefik-defaults.yaml
```
