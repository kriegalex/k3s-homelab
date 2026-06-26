# Proton Drive off-site backup (Immich / Nextcloud / Paperless)

Backs up the **irreplaceable** NFS-resident user data to Proton Drive (1.3 TB
plan, ~398 G of data). The CNPG database dumps and Longhorn PVC backups already
live in the QNAP S3 buckets; this fills the gap that those do **not** cover —
the actual photos, files, and documents on the mediaserver.

| Source (mediaserver 10.0.0.2, mounted read-only) | Size | Proton dest |
|--------------------------------------------------|------|-------------|
| `/mnt/user/immich`         (photos)    | ~36 G  | `protondrive:homelab-backup/immich`    |
| `/mnt/user/nextcloud`      (files)     | ~360 G | `protondrive:homelab-backup/nextcloud` |
| `/mnt/user/paperless/media`(documents) | ~1.5 G | `protondrive:homelab-backup/paperless` |

- **Tool:** rclone `protondrive` backend (Beta), pinned to **1.74.2**.
- **Mode:** `rclone copy` — additive, never deletes on Proton.
- **Schedule:** daily 04:00 UTC, `concurrencyPolicy: Forbid`.

Proton Drive has no S3/WebDAV API; rclone's reverse-engineered `protondrive`
backend is the only headless option. Set expectations: it is slower and more
rate-limited than real S3 — the initial ~360 G Nextcloud upload may take many
hours and should be run as a one-off Job (step 5), not left to cron.

---

## One-time bootstrap (you must do this — it needs your Proton credentials)

### 1. Install rclone on your workstation
```fish
paru -S rclone        # CachyOS / Arch; gives the current 1.74.x
```

### 2. Obscure the password
This account currently has **no 2FA**, so only the password is needed — rclone
re-logins unattended with username + password alone.

```fish
rclone obscure 'YOUR_PROTON_PASSWORD'        # -> <obscured-password>
```

> **If you re-enable 2FA later** (recommended — it also guards your email): add
> `otp_secret_key = <obscured>` to the config, where the value is your **TOTP
> secret seed** (the base32 string from 2FA setup, e.g. `JBSWY3DPEHPK3PXP`) run
> through `rclone obscure` — NOT a 6-digit code. rclone then mints its own codes
> and stays unattended. Also save Proton's 2FA **recovery codes** somewhere that
> is NOT Proton Pass, to avoid a self-lockout.

### 3. Build the config locally and test it
Create `rclone.conf` (anywhere temporary):
```ini
[protondrive]
type = protondrive
username = you@proton.me
password = <obscured-password>
# otp_secret_key = <obscured>     # ONLY if you re-enable 2FA (see step 2 note)
# mailbox_password = <obscured>   # ONLY if you use Proton "two-password mode"
```
Verify auth before deploying — this should list your Drive's folders:
```fish
rclone --config ./rclone.conf lsd protondrive:
```

### 4. Create the namespace + Secret (Secret is gitignored, never committed)
```fish
kubectl apply -f backup/protondrive/namespace.yaml
kubectl -n backup create secret generic protondrive-rclone-config \
  --from-file=rclone.conf=./rclone.conf
rm ./rclone.conf        # the cluster has it now
```

### 5. Apply PVC + CronJob, then kick the initial seed manually
```fish
kubectl apply -f backup/protondrive/rclone-config-pvc.yaml
kubectl apply -f backup/protondrive/cronjob.yaml

# Run the first (long) upload now instead of waiting for 04:00 cron:
kubectl -n backup create job protondrive-seed --from=cronjob/protondrive-backup
kubectl -n backup logs -f job/protondrive-seed
```

---

## Operations

- **Watch progress:** `kubectl -n backup logs -f job/<job-name>` (stats every 2m).
- **Verify on Proton:** `rclone --config ./rclone.conf size protondrive:homelab-backup/nextcloud`
  (or check sizes per category match the sources).
- **Re-auth / rotate creds:** update the Secret, then wipe the cached config so
  the new one is re-seeded:
  ```fish
  kubectl -n backup delete secret protondrive-rclone-config
  kubectl -n backup create secret generic protondrive-rclone-config --from-file=rclone.conf=./rclone.conf
  # force re-seed (clears the cached session on the PVC):
  kubectl -n backup delete pvc protondrive-rclone-config   # recreate via step 5 apply
  ```
- **Throttle upload** (if it saturates your uplink): add `--bwlimit 20M` to
  `COMMON` in `cronjob.yaml`.

## Notes / caveats

- Backend is **Beta**; a few account types have reported incompatibilities.
  Step 3's `lsd` test is the gate.
- `copy` never deletes — Proton usage only grows. With ~398 G into 1.3 TB
  there's ample room; revisit with `sync --backup-dir` if it ever tightens.
- Restore is `rclone copy protondrive:homelab-backup/<cat> <dest>` — pair it
  with the matching CNPG DB restore (Immich/Nextcloud/Paperless each need both
  their database AND these files).
- No backup-age alerting yet — a Prometheus rule on CronJob success is a
  sensible follow-up.
