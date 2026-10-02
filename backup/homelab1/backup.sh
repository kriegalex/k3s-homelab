#!/bin/sh
# Nightly backup of homelab1 to the QNAP's S3 endpoint, encrypted with rclone
# crypt (remote `hl1:`, defined in .env). See README.md for what is covered.
#
# Same bounded scheme as backup/exoscale-s3/: `rclone sync --backup-dir`
# mirrors each source, and whatever a run would delete or overwrite is moved to
# hl1:_archive/<run date>/ and purged after KEEP_DAYS. A source that fails its
# check is skipped (its mirror is left untouched) and the run exits 1.
set -eu

# Dead-man's switch (monitoring/deadman): /start now, the exit status at the end.
hc() { [ -z "${HC_URL:-}" ] || curl -fsS -m 10 --retry 3 -o /dev/null "${HC_URL}$1" || true; }
trap 'hc "/$?"' EXIT
hc /start

COMMON="--transfers=4 --checkers=8 --retries=3 --low-level-retries=10 \
        --log-level=INFO --stats=1m --stats-one-line"
ARCHIVE=_archive
TODAY=$(date -u +%F)
STAGE=/tmp/stage
STALE=""

rm -rf "$STAGE"
mkdir -p "$STAGE/gitea-db" "$STAGE/healthchecks-db"

# --- database dumps: consistent copies, never the live database files ------
DUMPS_OK=yes
echo "===== pg_dump gitea ====="
if ! pg_dump --format=custom --file="$STAGE/gitea-db/gitea.dump"; then
  echo "ERROR: pg_dump of gitea failed" >&2
  DUMPS_OK=no; STALE="$STALE gitea-db"
fi
echo "===== sqlite backup healthchecks ====="
if ! sqlite3 "file:/src/healthchecks/hc.sqlite?mode=ro" ".backup '$STAGE/healthchecks-db/hc.sqlite'"; then
  echo "ERROR: sqlite backup of healthchecks failed" >&2
  DUMPS_OK=no; STALE="$STALE healthchecks-db"
fi
if [ "$DUMPS_OK" = yes ]; then
  echo "===== sync dumps ====="
  # shellcheck disable=SC2086
  rclone sync "$STAGE" hl1:dumps --backup-dir "hl1:$ARCHIVE/$TODAY/dumps" $COMMON
fi

# --- /opt/stacks: compose files, .env, Gitea files, HA backup archives -------
# Excluded: the live Postgres and Redis directories (the dump above replaces
# them) and Gitea's regenerable caches. Of Home Assistant only its own backup
# archives are taken: they hold the config and a consistent recorder database.
# Guards against an empty or unmounted source mirroring "nothing":
if [ ! -s /src/stacks/gitea/data/gitea/conf/app.ini ]; then
  echo "ERROR: /src/stacks looks empty (no gitea app.ini) - skipping stacks" >&2
  STALE="$STALE stacks"
else
  if [ -z "$(find /src/stacks/homeassistant/config/backups -name '*.tar' -mtime -2 | head -n 1)" ]; then
    echo "ERROR: no Home Assistant backup newer than 2 days - check HA automatic backups" >&2
    STALE="$STALE ha-backup"   # still synced: the older archives are worth keeping
  fi
  echo "===== sync stacks ====="
  # shellcheck disable=SC2086
  rclone sync /src/stacks hl1:stacks --backup-dir "hl1:$ARCHIVE/$TODAY/stacks" $COMMON \
    --filter '- /gitea/postgresql/**' \
    --filter '- /gitea/redis/**' \
    --filter '- /gitea/data/tmp/**' \
    --filter '- /gitea/data/repo-archive/**' \
    --filter '- /gitea/data/gitea/log/**' \
    --filter '- /gitea/data/gitea/queues/**' \
    --filter '- /gitea/data/gitea/indexers/**' \
    --filter '+ /homeassistant/config/backups/**' \
    --filter '- /homeassistant/config/**' \
    --filter '+ **'
fi

# --- prune archive days older than KEEP_DAYS ---------------------------------
# By dated directory name, not object age: a server-side move keeps the
# original mtime (same reasoning as backup/exoscale-s3/cronjob.yaml).
CUTOFF=$(date -u -d "@$(( $(date -u +%s) - KEEP_DAYS * 86400 ))" +%Y%m%d)
for day in $(rclone lsf --dirs-only "hl1:$ARCHIVE" 2>/dev/null | tr -d /); do
  case "$day" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) echo "skip unexpected archive entry: $day"; continue ;;
  esac
  if [ "$(echo "$day" | tr -d -)" -lt "$CUTOFF" ]; then
    echo "===== purge $ARCHIVE/$day (older than ${KEEP_DAYS}d) ====="
    rclone purge "hl1:$ARCHIVE/$day"
  fi
done

if [ -n "$STALE" ]; then
  echo "FATAL: sources failed their check:$STALE" >&2
  exit 1
fi
echo "===== homelab1 backup complete ====="
