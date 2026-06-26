# Exoscale SOS off-site backup (Immich / Nextcloud / Paperless)

Fast, S3-native, **Swiss-hosted** off-site copy of the **irreplaceable**
NFS-resident user data — the photos/files/docs that the QNAP S3 (CNPG DB dumps
+ Longhorn PVCs) does **not** cover. This is the S3 counterpart to
`../protondrive/`; it exists because Proton Drive's reverse-engineered backend
is throughput-capped (single-stream, anti-abuse rate-limited) and the ~398 G
seed takes days.

| Source (mediaserver 10.0.0.2, mounted read-only) | Size | Dest (encrypted) |
|--------------------------------------------------|------|------------------|
| `/mnt/user/immich`          (photos)    | ~36 G  | `exoscale-crypt:immich`    |
| `/mnt/user/nextcloud`       (files)     | ~360 G | `exoscale-crypt:nextcloud` |
| `/mnt/user/paperless/media` (documents) | ~1.5 G | `exoscale-crypt:paperless` |

- **Provider:** Exoscale Simple Object Storage (S3-compatible), Swiss zones
  **ch-gva-2** (Geneva) / **ch-dk-2** (Zurich). Keeps data in Switzerland,
  same jurisdiction as Proton.
- **Cost:** ~€0.0198/GB/mo storage → **~€8/mo** for ~400 G. Egress €0.02/GB →
  **~€8** for a full ~400 G restore. API requests are free.
- **Tool:** rclone `s3` backend + `crypt` wrapper, pinned to **1.74.2**.
- **Encryption:** client-side AES (`crypt`) — Exoscale stores only opaque blobs,
  filenames included. Zero-knowledge, same as Proton.
- **Mode:** `rclone copy` — additive, never deletes on S3.
- **Schedule:** daily 02:00 UTC, `concurrencyPolicy: Forbid`.

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
