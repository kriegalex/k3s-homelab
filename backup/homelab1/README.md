# homelab1 backup

`homelab1` (10.0.0.50) runs Gitea (repo origin, container registry, CI runner),
Home Assistant and the dead-man's-switch Healthchecks — all outside the cluster,
so none of the cluster's backup jobs cover it. This stack backs it up nightly to
the QNAP's S3 endpoint, encrypted with rclone `crypt`.

It runs on homelab1 itself as a Docker Compose stack in `/opt/stacks/backup`:
busybox `crond` starts `backup.sh` at 01:30 (Europe/Brussels).

## What is covered

| Data | How | Remote path (inside `hl1:`) |
|------|-----|------------------------------|
| Gitea database | `pg_dump --format=custom` over the `gitea_gitea-network` | `dumps/gitea-db/gitea.dump` |
| Healthchecks database | SQLite online backup, read-only | `dumps/healthchecks-db/hc.sqlite` |
| Gitea files: `app.ini`, registry packages, repos, LFS, SSH host keys, JWT key, runner registration | file sync of `/opt/stacks/gitea` | `stacks/gitea/` |
| Home Assistant config + history | HA's own automatic backups (`/config/backups/*.tar`) | `stacks/homeassistant/config/backups/` |
| Every stack's compose file and `.env`, nginx config, certbot hooks | file sync of `/opt/stacks` | `stacks/` |

Not copied, on purpose: the live Postgres and Redis directories (the dump
replaces them; Redis holds only cache and sessions), Gitea's logs, queues,
indexers, `tmp/` and `repo-archive/` (all regenerated), Home Assistant's live
`config/` beyond its backup archives, the Let's Encrypt volume (re-issued by
certbot), and the Arcane/Dockge UI state.

The `.env` files contain secrets — the Gitea database password, the Infomaniak
DNS API token, the runner registration token, this stack's own QNAP key — which
is why everything goes through `crypt`.

## Retention

Bounded, same scheme as `backup/exoscale-s3/`: `rclone sync --backup-dir`
mirrors each source, and whatever a run would delete or overwrite is moved to
`hl1:_archive/<run date>/` and purged after `KEEP_DAYS` (30) by directory name.
The dumps change every night, so the archive holds 30 daily versions of both
databases. Home Assistant keeps 3 backups locally; older ones live on in the
archive for 30 days.

A source that fails its check is skipped — its mirror is left as it was — and
the run exits 1, which the Healthchecks check turns into a page:

| Check | Fails when |
|-------|------------|
| `gitea-db`, `healthchecks-db` | the dump fails (the dumps are then not synced at all) |
| `stacks` | `/opt/stacks/gitea/data/gitea/conf/app.ini` is missing — an empty or unmounted source |
| `ha-backup` | no HA backup newer than 2 days; the stacks sync still runs |

## Install

1. **QNAP:** in QuObjects, create bucket `homelab1-backup` and an access key
   whose permissions cover that bucket only.
2. **Home Assistant:** Settings → System → Backups → automatic backups:
   daily at **01:00** (before this job), keep **3**, location *This system*.
   Store HA's **backup encryption key** in the password manager — HA encrypts
   its archives with it, and a restore needs it.
3. **Healthchecks:** add check `homelab1-backup` — cron `30 1 * * *`,
   Europe/Brussels, grace 1 h — on the ntfy integration (see
   `monitoring/deadman/README.md`). Copy its ping URL.
4. **Stack:** copy this directory to homelab1 and fill in `.env`:

   ```fish
   scp -r backup/homelab1 admin@10.0.0.50:/opt/stacks/backup
   ssh admin@10.0.0.50
   ```
   ```bash
   cd /opt/stacks/backup
   cp .env.example .env && chmod 600 .env
   docker compose build
   # encryption passwords: generate two, keep the CLEAR values in the password manager,
   # put the obscured output into RCLONE_CONFIG_HL1_PASSWORD / _PASSWORD2
   openssl rand -base64 30
   docker compose run --rm --entrypoint rclone backup obscure '<clear password>'
   # then PGPASSWORD, the QNAP key and HC_URL
   docker compose up -d
   ```

## Verify

```bash
docker compose exec backup backup.sh                # one run now, output to the terminal
docker compose exec backup rclone lsf -R hl1: | head   # decrypted listing
docker logs homelab1-backup                         # scheduled runs
```

The Healthchecks check shows *started*, then a success ping. The first run
uploads ~1.6 GB over the LAN.

## Restore

Every command runs in this stack's container, which already holds the remote
definitions: `docker compose run --rm -v /restore:/restore --entrypoint rclone backup …`.

- **Point in time:** `copy hl1:_archive/<date>/<path> /restore/` for anything
  deleted or overwritten in the last 30 days; `copy hl1:dumps /restore/dumps`
  for the latest databases.
- **Gitea:** stop the stack; restore `stacks/gitea/` into `/opt/stacks/gitea`;
  start `postgresql` alone on an empty data directory; then
  `pg_restore --clean --if-exists -h gitea-postgresql -U gitea -d gitea gitea.dump`
  (from this container, `PG*` already set); start the rest.
- **Home Assistant:** on a fresh install, onboarding → *Restore from backup*,
  upload the newest `.tar` and give HA's backup encryption key.
- **Healthchecks:** stop it, copy `hc.sqlite` into the `healthchecks-data`
  volume as `/data/hc.sqlite` (owned by the image's `hc` user), start it.

Without the two clear `crypt` passwords from the password manager, nothing here
can be read.
