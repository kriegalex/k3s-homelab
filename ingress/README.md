# Ingress

Ingress for the cluster is provided by **Traefik v3** with TLS certificates
issued by **cert-manager** (DNS-01 via Infomaniak / Route53).

```
ingress/
├── README.md            # this file
├── traefik/             # Traefik install + middlewares (the only ingress controller)
│   ├── README.md
│   ├── values.yaml
│   ├── ingressroute-dashboard.yaml
│   └── middlewares/
├── cert-manager/        # cert-manager install + ClusterIssuers
│   └── README.md
└── cluster-issuer.yaml  # template ClusterIssuer (Route53)
```

ingress-nginx was the previous controller and has been fully removed; see
`~/workspace/traefik-migration/MIGRATION_GUIDE.md` if you need the historical
playbook.

## Bootstrap order

1. **MetalLB** (cluster-prereq, separate repo) — provides LoadBalancer IPs.
2. **cert-manager** (`cert-manager/`) — install controller + apply ClusterIssuers.
3. **Traefik** (`traefik/`) — install controller + apply middlewares + dashboard.
4. **Apps** — each app's `values.yaml` references the cert-manager ClusterIssuer
   in its Ingress annotations and sets `ingressClassName: traefik`.

## Per-Ingress conventions

- Every `Ingress` sets `ingressClassName: traefik` explicitly. Traefik's
  IngressClass is **not** the cluster default (deliberate — see
  `traefik/values.yaml`), so an unset class will not be picked up.
- TLS certs come from cert-manager via the standard `cert-manager.io/cluster-issuer`
  annotation; Traefik consumes them through the standard `tls.secretName` field.
- Middleware is applied via the
  `traefik.ingress.kubernetes.io/router.middlewares` annotation, with
  `<namespace>-<name>@kubernetescrd` references. `allowCrossNamespace` is
  `false`, so a Middleware is only addressable from same-namespace Ingresses.
  Cluster-wide middlewares (e.g. `traefik/redirect-https`) are referenced from
  any namespace.

## Testing a new app's Ingress

```bash
kubectl get ingress -n <ns> <name> -o yaml
kubectl get svc -n traefik traefik    # confirm 10.0.0.20 / EXTERNAL-IP
curl -I https://<host>                # 200/301 + valid Let's Encrypt cert chain
```

If the cert is stuck `READY=False`:

```bash
kubectl get certificate,certificaterequest,order,challenge -A | grep <host>
kubectl -n cert-manager logs deploy/cert-manager
```

## External-service Ingresses

If you need to route to a service running outside the cluster (host VM, NAS,
etc.) create a headless `Service` + `Endpoints` pair in the same namespace as
the Ingress, then point the Ingress backend at the Service name as usual.
There are no live external-service Ingresses today; the historical examples
under `ingress/rules/` were removed when their backends moved into the cluster.
