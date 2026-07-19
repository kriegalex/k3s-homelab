# tls-fetch

Tiny in-cluster HTTP proxy that fetches TLS-fingerprint-walled pages (DataDome/Akamai JA3
blocks) using [`curl_cffi`](https://github.com/lexiforest/curl_cffi)'s Chrome impersonation,
so the n8n apartment-monitor can enrich listings from portal detail pages that a plain HTTP
client can't reach.

## Why

Portal alert e-mails (Comparis, homegate, …) link to listing detail pages behind DataDome.
Plain `curl`/Node fetch gets **403 at the TLS layer**; `curl_cffi(impersonate=chrome)` clears
it (verified: Comparis dispatcher link 403→200, full `__NEXT_DATA__` JSON with description,
amenities, floor, GPS, photos, **and the listing agency**). n8n's HTTP Request node can't
spoof TLS, so `APPT 21 Enrich` GETs this service instead.

## API

```
GET /fetch?url=<url>[&impersonate=chrome]   → {status, final_url, content_type, truncated, datadome, body}
GET /healthz                                → {ok: true}
```

- `url` host must match `ALLOWED_HOSTS` (in-app allowlist — blocks SSRF to internal/metadata
  endpoints) and must resolve to a public IP. Real-estate portals only.
- Follows redirects (the Comparis `dispatcher/go?cgid=` link → the real detail page).
- Cluster-internal only: `http://tls-fetch.n8n.svc.cluster.local:8080`. No Ingress.

### DataDome session replay (immoscout24 / homegate / SMG pool)

Some portals (immoscout24.ch, homegate.ch) block **live** listing/search pages with DataDome
that curl_cffi's TLS impersonation alone does **not** clear (only expired listings 404 through).
The only working path is to replay a **solved `datadome` cookie** captured from a real browser:

```
GET /fetch?url=<url>
  X-DD-Cookie: <datadome cookie value from the browser>
  X-DD-UA:     <exact navigator.userAgent from that same browser>
```

- Works because DataDome binds the token to **IP + UA + TLS fingerprint**: the browser solves the
  challenge on the home network, and this sidecar egresses that **same home WAN IP**. A datacentre
  proxy would break the IP binding.
- The token **rolls** — every `200` response carries a fresh `datadome`, returned in the JSON
  `datadome` field. **The caller must persist it and send the newest one next time** to keep the
  session alive (static token dies in hours; rolled token lasts far longer). Session also dies on
  home-IP change, long idle, or behavioural flags → keep cadence human, alert on the first `403`.
- Headers are used (not query params) so the token stays out of URLs/logs. Cookie name is
  `datadome` for the whole SMG pool.

### Mail click-tracker resolution (homegate alerts)

Homegate alert e-mails wrap the listing link in a SendGrid click-tracker
(`*.sendgrid.net/ls/click?...`) instead of a direct URL. When the target host is a
`REDIRECTOR_HOSTS` entry, the sidecar first resolves it to the real portal URL, then
applies the cookie to that:

- Resolution follows the `Location` header hop-by-hop (`allow_redirects=False`) **without
  the cookie**, so the portal is never fetched un-authenticated — no cookie-less 403 that
  would ding the home IP's DataDome reputation. (The cookie also would not survive a
  cross-domain redirect anyway — verified: single-call sendgrid+cookie → 403, resolve-then-
  fetch → 200.)
- Only a resolved host that is itself in `ALLOWED_HOSTS` (a known portal) is then fetched,
  with the cookie. Tracking query params are stripped. Redirector hosts must be in **both**
  `ALLOWED_HOSTS` (to accept the inbound link) and `REDIRECTOR_HOSTS` (to trigger resolution).
- Direct portal links (immoscout `/louer/<id>`) are not redirectors → fetched straight with
  the cookie, no extra request. So this path is homegate-only and transparent to the caller.

## Deploy

```bash
kubectl apply -f tls-fetch.yaml    # ConfigMap (server.py) + Deployment + Service, ns n8n
kubectl rollout status deploy/tls-fetch -n n8n
```

Registry-less: runs stock `python:3.12-slim` and `pip install`s `curl_cffi` (pinned) into an
emptyDir at startup (PyPI egress from ns `n8n` is open). Non-root, readOnlyRootFilesystem.

## Maintenance

- **Bump `curl_cffi`** periodically — Chrome TLS profiles rotate and an outdated
  impersonation eventually gets flagged. Edit the pinned version in `tls-fetch.yaml`
  (`pip install ... "curl_cffi==X.Y.Z"`) and `kubectl rollout restart deploy/tls-fetch -n n8n`.
- If a portal escalates from TLS-only to a JS/behavioral challenge, curl_cffi won't be
  enough — fall back to a managed unblocker API (see memory `datadome-tls-fingerprint-bypass`).
- Add new portal hosts to `ALLOWED_HOSTS` in the Deployment env as alert sources expand.
