#!/bin/sh
# busybox crond starts jobs with an empty environment, so the container's
# environment (from .env) is saved to a root-only file that each run sources.
set -eu

umask 077
export -p | grep -v -E '^export (HOME|HOSTNAME|PWD|SHLVL)=' > /run/backup.env

# Job output goes to PID 1's stdout, i.e. `docker logs homelab1-backup`.
echo "$SCHEDULE /bin/sh -c '. /run/backup.env && /usr/local/bin/backup.sh' > /proc/1/fd/1 2>&1" \
  > /etc/crontabs/root

echo "homelab1-backup: schedule '$SCHEDULE' ($TZ)"
exec crond -f -l 8
