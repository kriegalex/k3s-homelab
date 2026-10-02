# Backup runner for homelab1: pg_dump + sqlite3 for consistent database copies,
# rclone for the upload, busybox crond for the schedule.
FROM alpine:3.22

# Same rclone release as the cluster backup jobs (backup/exoscale-s3/).
COPY --from=rclone/rclone:1.74.2 /usr/local/bin/rclone /usr/local/bin/rclone

# postgresql17-client matches the gitea-postgresql server (postgres:17-alpine).
RUN apk add --no-cache postgresql17-client sqlite curl tzdata

COPY backup.sh entrypoint.sh /usr/local/bin/
RUN chmod 755 /usr/local/bin/backup.sh /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
