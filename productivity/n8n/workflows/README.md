# n8n workflows — appart-bulle

Version-controlled exports of the `appart-bulle` apartment-monitor workflows running on
n8n.lourenco.ch (n8n 2.30.7). The live instance is the runtime; these JSONs are the
committed source of truth for the workflow logic, same convention as `values.yaml` for
Helm charts.

| File | Workflow | Trigger |
|------|----------|---------|
| `appt-10-src-immobilier.json` | immobilier.ch scraper (Bulle, 2 pages) | cron `5-59/10` |
| `appt-11-src-regiebulle.json` | Régie Bulle SA RSS | RSS poll `*/10` |
| `appt-13-src-gerofinance.json` | Gerofinance scraper (NPA 1630 + 1635) | cron `2-59/10` |
| `appt-14-src-gruyere-sallin.json` | Gruyère Immo JSON API + Sallin Immobilier scraper | cron `7-59/10` |
| `appt-15-src-email-alerts.json` | Portal alert e-mails (homegate/immoscout24/newhome/Comparis/petitesannonces) via Gmail IMAP, label `Appart-Bulle` | IMAP trigger (instant) |
| `appt-20-ingest.json` | Normalize (cross_key) → upsert → enrich (APPT 21) → cross-portal dedup → LLM triage → ntfy + Telegram (fit ≥ 60, photo) | called by sources |
| `appt-21-enrich.json` | For `email-*` listings: fetch the detail page via `tls-fetch` (curl_cffi), backfill description/amenities/floor/GPS/images/agency, join `agency_reputation`. Comparis via `__NEXT_DATA__`; immoscout24/homegate (SMG) via replayed DataDome cookie from `portal_cookies` with a circuit breaker (expired token → zero fetches + ntfy) | called by APPT 20 |
| `appt-50-daily-digest.json` | 08:00 Telegram digest of last-24 h listings + DataDome cookie-health footer (token status & age per portal) | cron `0 8 * * *` |
| `appt-90-error-handler.json` | Error workflow → ntfy `homelab-k3s` | Error Trigger |
| `appt-99-test-inject.json` | Auth-protected test webhook `/webhook/appart-inject` | Webhook |

## Sync convention

- **Live edit → export**: after changing a workflow in the UI/API, re-export it here
  (`GET /api/v1/workflows/<id>`, keep only `name`/`nodes`/`connections`/`settings`, plus the
  `meta.exportedFrom` id) and commit.
- **Import**: `POST /api/v1/workflows` with the JSON body (strip `meta` if the API rejects
  extra fields), re-attach the `appart-bulle` tag, publish. Credentials are referenced by
  **name + instance-local id** and contain no secret material — on a fresh instance,
  recreate credentials first, then fix the ids in the JSON (or re-pick them in the UI).
- Credentials used: `apartments-db` (Postgres), `ntfy homelab-publisher` (header auth),
  `Telegram account`, `Anthropic (apartments)`, `appart-imap (gmail)` (IMAP, Gmail app
  password — revocable at myaccount.google.com/apppasswords).
- Listing store: database `apartments` in the n8n-db CNPG cluster
  (`../apartments-database.yaml`), schema in `../apartments-schema.sql` (tables `listings`,
  `agency_reputation`, `portal_cookies`).
- Enrichment sidecar: `../tls-fetch/` — in-cluster curl_cffi proxy that APPT 21 GETs to
  fetch TLS-fingerprint-walled portal detail pages (Comparis etc.).

## DataDome cookie re-seed (immoscout24 / homegate)

SMG portals gate live pages with DataDome; APPT 21 enriches them by replaying a solved
`datadome` cookie held in `portal_cookies`. The token rolls automatically on every success,
but dies on a home-IP change, long idle, or a behavioural flag. When it expires the circuit
breaker flips the row to `status='expired'`, fires one ntfy alert, and **stops all fetches
for that portal** (deliberately — see `tls-fetch/README.md`); the APPT 50 digest footer then
shows 🔴 EXPIRÉ. To resume, capture a fresh cookie from a real browser on the **home network**
and write it back:

1. Open `https://www.immoscout24.ch` (or `https://www.homegate.ch`) and let the page fully
   load (solve the captcha if shown).
2. DevTools → Application → Cookies → copy the **`datadome`** value; Console → copy
   `navigator.userAgent`.
3. Write it back (resolve the CNPG primary first — it can fail over):

   ```bash
   PRIMARY=$(kubectl get cluster n8n-db -n n8n -o jsonpath='{.status.currentPrimary}')
   kubectl exec -n n8n "$PRIMARY" -c postgres -- psql -U postgres -d apartments -c \
     "UPDATE portal_cookies SET datadome='<TOKEN>', user_agent='<UA>', \
      status='active', last_ok=now(), last_checked=now(), updated_at=now() \
      WHERE portal='immoscout24';"
   ```

The next morning's digest footer should read ✅ with a fresh age. Never commit token values —
`portal_cookies` lives in the DB only.

Design/run-book: `claude-docs/apartment-monitor-n8n.md` (local, uncommitted).
