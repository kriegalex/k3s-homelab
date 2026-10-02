# Exoscale SOS off-site backup

Fast, S3-native, **Swiss-hosted** off-site copy. Two CronJobs, both in namespace
`backup`, both writing through the same encrypted remote:

| Job | Manifest | Covers | Size | Schedule |
|-----|----------|--------|------|----------|
| `exoscale-s3-backup` | `cronjob.yaml` | NFS user data from mediaserver | ~398 G | 02:00 Europe/Brussels |
| `exoscale-s3-cluster-backup` | `cronjob-cluster.yaml` | 7 CNPG buckets + etcd snapshots | ~4.2 G | 03:30 Europe/Brussels |

This is the S3 counterpart to `../protondrive/`; it exists because Proton Drive's
reverse-engineered backend is throughput-capped (single-stream, anti-abuse
rate-limited) and the ~398 G seed takes days.

**User data** (mediaserver 10.0.0.2, mounted read-only):

| Source | Size | Dest (encrypted) |
|--------|------|------------------|
| `/mnt/user/immich`          (photos)    | ~36 G  | `exoscale-crypt:immich`    |
| `/mnt/user/nextcloud`       (files)     | ~360 G | `exoscale-crypt:nextcloud` |
| `/mnt/user/paperless/media` (documents) | ~1.5 G | `exoscale-crypt:paperless` |

**Cluster state** — these are payload files' missing half. Without them the
off-site copy is metadata-blind: immich keeps photo blobs but loses albums,
faces and timeline; nextcloud keeps file blobs but loses shares and the file
tree; paperless keeps scans but loses OCR text and tags.

| Source | Size | Dest (encrypted) |
|--------|------|------------------|
| `qnap-s3:{dealwatch,immich,event-manager,n8n,nextcloud,paperless,vigie}-backups` | ~2.4 G total, ~28 000 objects | `exoscale-crypt:cnpg/<app>` |
| `/var/lib/rancher/k3s/server/db/snapshots` (hostPath on k3s-server1) | ~117 M per snapshot, ~1.9 G retained on the node | `exoscale-crypt:etcd` |

Longhorn's volume backups (`qnap-s3:longhorn`, ~253 G) are **deliberately not
copied** — they would more than double the bill for the most reconstructible
tier, since those PVCs' real content is either the databases or the NFS data,
both already covered. The one-line change to enable it is commented in
`cronjob-cluster.yaml`.

- **Provider:** Exoscale Simple Object Storage (S3-compatible), Swiss zones
  **ch-gva-2** (Geneva) / **ch-dk-2** (Zurich). Keeps data in Switzerland,
  same jurisdiction as Proton.
- **Cost:** ~€0.0198/GB/mo storage → **~€8/mo** for ~400 G; the cluster-state
  job adds roughly **€0.20/mo** at steady state (mirror + 30 d archive). Egress €0.02/GB → **~€8** for a full ~400 G
  restore. API requests are free.
- **Tool:** rclone `s3` backend + `crypt` wrapper, pinned to **1.74.2**.
- **Encryption:** client-side AES (`crypt`) — Exoscale stores only opaque blobs,
  filenames included. Zero-knowledge, same as Proton. This matters more for the
  cluster job than the data one: an etcd snapshot contains every unencrypted
  Secret in the cluster, so it must never reach a plain bucket.
- **Mode:** `rclone sync --backup-dir` — the destination mirrors the source, and
  whatever a run would delete or overwrite is moved into a dated archive
  instead (see *Retention*). A local deletion or corruption cannot destroy the
  off-site copy, and nothing is kept forever. The bucket is also versioned,
  with a lifecycle rule that bounds the old versions (see *Bucket versioning
  and lifecycle*).

## Retention

Every tier is bounded. Nothing here accumulates indefinitely.

| Job | Mirror is bounded by | Deleted/overwritten files kept in | For |
|-----|----------------------|-----------------------------------|-----|
| `exoscale-s3-backup` | the live data on mediaserver | `exoscale-crypt:_archive-data/<date>/<category>/` | `KEEP_DAYS` = 90 |
| `exoscale-s3-cluster-backup` | barman `retentionPolicy: 30d` per ObjectStore; k3s `etcd-snapshot-retention: 14` | `exoscale-crypt:_archive-cluster/<date>/…` | `KEEP_DAYS` = 30 |

- `<date>` is the UTC day of the run that archived the file. Each run ends by
  purging archive days older than `KEEP_DAYS`, **by directory name** — a
  server-side move keeps a file's original mtime, so pruning by object age
  would purge an old photo the day after it was archived.
- Each source is checked before it is synced: the NFS categories must be
  non-empty, each CNPG bucket must hold something newer than 8 days (the
  weekly base backup — an idle database archives no WAL for weeks), and the
  etcd directory something newer than 2 days. A failed check fails the job
  (`KubeJobFailed`) instead of archiving a whole category because a share was
  not mounted. In the cluster job a stale source skips only itself; the other
  sources still sync before the job exits non-zero.
- A source that loses files wholesale (an Unraid disk missing from the array)
  moves them to the archive and re-uploads them when they return: bandwidth,
  not data, for `KEEP_DAYS`.
- To change a window, edit `KEEP_DAYS` in the manifest. Shortening it purges
  the excess on the next run.

> ⚠️ **The crypt password is the only key to this backup.** If you lose it, the
> data is unrecoverable — Exoscale cannot help (that's the point). Store it in
> Proton Pass / a password manager **and** an offline copy before seeding.

---

## One-time bootstrap (you must do this — it needs an Exoscale account)

### 1. Provision Exoscale SOS
In the Exoscale Console → **Storage**:
1. Create a bucket (e.g. `homelab-backup`) in a **Swiss zone** — `ch-gva-2`
   (Geneva) or `ch-dk-2` (Zurich).
2. **IAM → API Keys:** create an API key/secret scoped to SOS for that bucket.

> The endpoint is zone-pinned: `https://sos-<zone>.exo.io`. The `region` and the
> endpoint's `<zone>` **must match the bucket's zone** or you get empty listings
> / odd errors instead of a clean failure.

### 2. Install rclone on your workstation
```fish
paru -S rclone        # CachyOS / Arch
```

### 3. Generate the crypt key (SAVE IT — see warning above)
```fish
# a long random passphrase, then obscure it for the config:
openssl rand -base64 32                       # -> SAVE this plaintext somewhere safe
rclone obscure 'THE_PASSPHRASE_FROM_ABOVE'    # -> <obscured-password> for the conf
# optional second "salt" passphrase (recommended), same process:
rclone obscure 'A_SECOND_RANDOM_PASSPHRASE'   # -> <obscured-password2>
```

### 4. Build the config locally and test it
Create `rclone.conf` (anywhere temporary — `**/rclone.conf` is gitignored):
```ini
[exoscale-s3]
type = s3
provider = Other
access_key_id = <your-exoscale-api-key>
secret_access_key = <your-exoscale-api-secret>
endpoint = https://sos-ch-gva-2.exo.io
region = ch-gva-2
acl = private

[exoscale-crypt]
type = crypt
remote = exoscale-s3:homelab-backup        # <bucket>[/optional-prefix]
password = <obscured-password>
password2 = <obscured-password2>           # omit the line if you skipped step 3's salt
```
Verify auth + crypt before deploying (writes & reads back a tiny test file):
```fish
rclone --config ./rclone.conf lsd exoscale-s3:                  # lists the bucket
echo hi | rclone --config ./rclone.conf rcat exoscale-crypt:_selftest
rclone --config ./rclone.conf cat exoscale-crypt:_selftest      # -> hi
rclone --config ./rclone.conf delete exoscale-crypt:_selftest
```

### 5. Create the Secret (gitignored, never committed)
```fish
kubectl apply -f backup/protondrive/namespace.yaml      # 'backup' ns (shared; skip if it exists)
kubectl -n backup create secret generic exoscale-rclone-config \
  --from-file=rclone.conf=./rclone.conf
rm ./rclone.conf        # the cluster has it now
```

### 6. Apply the CronJob, then kick the initial seed manually
```fish
kubectl apply -f backup/exoscale-s3/cronjob.yaml

# Run the first full upload now instead of waiting for 02:00 cron:
kubectl -n backup create job exoscale-s3-seed --from=cronjob/exoscale-s3-backup
kubectl -n backup logs -f job/exoscale-s3-seed
```

---

## QNAP S3 remote (required by the cluster-state job)

`cronjob-cluster.yaml` reads the CNPG buckets straight from the QNAP's S3
endpoint, so the **same** `exoscale-rclone-config` Secret must also carry a
`[qnap-s3]` remote. The Secret is built from the whole file, so adding a remote
means editing the local `rclone.conf` and recreating it.

Credentials are the QNAP S3 access key/secret — the same pair the CNPG
ObjectStores use, readable in the QNAP GUI under the S3 service. Append:

```ini
[qnap-s3]
type = s3
provider = Other
endpoint = http://10.0.0.7:8010
access_key_id = <QNAP_S3_ACCESS_KEY>
secret_access_key = <QNAP_S3_SECRET_KEY>
force_path_style = true
# The QNAP endpoint is plain HTTP on the flat LAN (review-2026-09-19, S-9).
# SigV4 keeps the secret key off the wire, but the objects themselves cross in
# cleartext. Switch this to https:// once TLS is enabled on the S3 service.
```

Then replace the Secret and apply the job:

```fish
kubectl -n backup create secret generic exoscale-rclone-config \
  --from-file=rclone.conf=./rclone.conf \
  --dry-run=client -o yaml | kubectl -n backup apply -f -

kubectl apply -f backup/exoscale-s3/cronjob-cluster.yaml

# Verify the remote resolves before trusting the schedule:
kubectl -n backup create job cluster-seed --from=cronjob/exoscale-s3-cluster-backup
kubectl -n backup logs -f job/cluster-seed
```

The first run seeds ~4.2 G and takes about 15 minutes — the ~28 000 small WAL
objects dominate, not the bytes. Nightly runs only carry the day's WAL and one
etcd snapshot. Confirm both
prefixes landed:

```fish
rclone lsd exoscale-crypt:cnpg --config ./rclone.conf
rclone ls  exoscale-crypt:etcd --config ./rclone.conf | tail
```

If `etcd` is empty, check that the job scheduled onto **k3s-server1** — the
snapshots are a hostPath on the control-plane node, and the `nodeSelector` plus
control-plane toleration are what put it there.

---

## Bucket versioning and lifecycle

The bucket has versioning enabled: an object that is deleted or overwritten
stays recoverable as a noncurrent version. On its own versioning would break
the retention rule — every file the jobs purge from the archive would live on
as a version forever — so it runs **together with** the rules in
`lifecycle.json`:

| Rule | Effect |
|------|--------|
| `expire-noncurrent-versions` | noncurrent versions are deleted after 30 days |
| `remove-dangling-delete-markers` | delete markers with no versions left behind them are removed |
| `abort-stale-multipart-uploads` | incomplete multipart uploads are aborted after 7 days |

Worst-case lifetime of a deleted file is therefore `KEEP_DAYS` in the archive
plus 30 days as a noncurrent version of the purged archive copy (120 days for
user data, 60 for cluster state).

Versioning protects against accidental deletion (a bad sync, a script bug),
not against a stolen in-cluster key: that key can still delete noncurrent
versions and change the bucket's versioning and lifecycle settings.

Both settings are managed with the `exo` CLI (`paru -S exoscale-cli`), using a
workstation API key whose IAM role is limited to the `sos` service — not the
in-cluster key. Never enable versioning on a bucket without the lifecycle
rules; when recreating the bucket, apply them first:

```fish
exo storage bucket lifecycle set sos://k3s-homelab-backup backup/exoscale-s3/lifecycle.json -z ch-gva-2
exo storage bucket versioning enable sos://k3s-homelab-backup -z ch-gva-2
exo storage bucket lifecycle show sos://k3s-homelab-backup -z ch-gva-2
exo storage bucket versioning status sos://k3s-homelab-backup -z ch-gva-2
```

Lifecycle evaluation runs daily at midnight UTC. Restoring a noncurrent
version goes through the underlying remote's version flags, e.g.
`rclone --s3-version-at "2026-01-31 12:00:00" copy exoscale-crypt:nextcloud/path /restore/`.

## Operations

- **Watch progress:** `kubectl -n backup logs -f job/<job-name>` (stats every 1m).
- **Verify size:** `rclone --config ./rclone.conf size exoscale-crypt:nextcloud`
  (decrypts sizes; should track the source).
- **Throttle upload** (if it saturates your uplink): add `--bwlimit 50M` to
  `COMMON` in `cronjob.yaml`.
- **Tune speed vs memory:** raise `--transfers` *or* `--s3-chunk-size`, not
  both — peak RAM ≈ `transfers * s3-upload-concurrency * chunk-size` (must stay
  under the 4Gi limit). If a run OOMs, lower `--transfers` first.
- **Rotate creds / key:** update the local `rclone.conf`, then:
  ```fish
  kubectl -n backup delete secret exoscale-rclone-config
  kubectl -n backup create secret generic exoscale-rclone-config --from-file=rclone.conf=./rclone.conf
  ```
  (No PVC to clear — S3 auth is stateless.) **Never** change the crypt
  password/salt after seeding, or already-uploaded data becomes unreadable.

## Restore

Restore needs the **same `rclone.conf`** (the crypt key) — keep it with your
disaster-recovery docs, not only in the cluster.
```fish
rclone --config ./rclone.conf copy exoscale-crypt:nextcloud /restore/nextcloud

# a file deleted or overwritten within the retention window:
rclone --config ./rclone.conf lsf exoscale-crypt:_archive-data/          # archive days
rclone --config ./rclone.conf copy exoscale-crypt:_archive-data/2026-01-31/nextcloud/path/to/file /restore/
```
Pair it with the matching CNPG DB restore (Immich/Nextcloud/Paperless each need
both their database AND these files).

## Relationship to the Proton Drive job

Both jobs read the same read-only NFS sources and can run side by side (offset
schedules: Exoscale 02:00, Proton 04:00) for dual off-site copies, both in
Swiss jurisdiction. Once this S3 path is proven, decide whether to retire the
slow Proton job or keep it as a second independent provider. No backup-age
alerting yet — a Prometheus rule on CronJob success is a sensible follow-up
(same gap as Proton).
