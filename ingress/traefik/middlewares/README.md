# Traefik Middlewares & ServersTransports

Cluster-wide CRDs consumed by Ingress resources via the
`traefik.ingress.kubernetes.io/router.middlewares` annotation
(`<namespace>-<name>@kubernetescrd[,...]`).

`allowCrossNamespace: false` is set on Traefik (`../values.yaml`), so a
Middleware is only addressable from Ingresses in the same namespace.

| File | Kind | Namespace | Name | Used by | What it does |
| --- | --- | --- | --- | --- | --- |
| `redirect-https.yaml` | `Middleware` | `traefik` | `redirect-https` | `deltabadger/deltabadger`, `n8n/n8n` | Permanent 301 to `https://` |
| `nextcloud.yaml` | `Middleware` | `nextcloud` | `nextcloud-wellknown-dav` | `nextcloud/nextcloud` | 301 `/.well-known/{card,cal}dav` → `/remote.php/dav/` |
| `nextcloud.yaml` | `Middleware` | `nextcloud` | `nextcloud-wellknown-rewrite` | `nextcloud/nextcloud` | Rewrite `/.well-known/{webfinger,nodeinfo,host-meta,host-meta.json}` → `/index.php/.well-known/...` |
| `nextcloud.yaml` | `Middleware` | `nextcloud` | `nextcloud-security-headers` | `nextcloud/nextcloud` | Strip `Server` and `X-Powered-By` response headers |
| `nextcloud.yaml` | `Middleware` | `nextcloud` | `nextcloud-cors` | `nextcloud/nextcloud` | CORS for `cloud.lourenco.ch` (WebDAV verbs included) |
| `paperless-body-64m.yaml` | `Middleware` | `paperless` | `body-limit-64m` | `paperless/paperless-ngx` | 64 MiB request-body buffer for Paperless uploads |
| `collabora-timeout.yaml` | `ServersTransport` | `nextcloud` | `long-timeout-600` | (referenced by Service spec, not annotation) | 600s response/idle timeouts for Collabora long polls |

## Why no global request-body buffering for Nextcloud

Traefik streams request bodies by default with no size cap — that is the
desired behavior for chunked uploads and large WebDAV PUTs. A `Buffering`
middleware would force full request buffering (memory + disk spool) before
forwarding (Traefik issue #12407). Upload size is enforced by Nextcloud /
PHP (`upload_max_filesize`, `post_max_size`) instead. Do **not** add a
buffering middleware to the `nextcloud/nextcloud` ingress.

## Adding a middleware

1. Add the YAML here (or extend an existing file with a `---` separator).
2. `kubectl apply -f <file>`.
3. Reference from the consuming Ingress' annotation; if the consumer lives
   in a different namespace, the cross-namespace flag (`allowCrossNamespace`
   in `../values.yaml`) must be flipped — currently `false` deliberately.
