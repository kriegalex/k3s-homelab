# Dead-man's switch

Every other alert in this lab is the cluster *sending* something: Prometheus →
Alertmanager → alertmanager-ntfy → ntfy, all four in-cluster. When the cluster
is what broke, nothing is sent, and silence looks like health. This inverts it:
the cluster and the backup jobs send "I'm alive" pings to a watcher **outside
the cluster**, and the watcher pages when the pings **stop**.

The watcher is a self-hosted [Healthchecks](https://healthchecks.io/docs/self_hosted/)
container on `homelab1` (10.0.0.50), notifying through the public **ntfy.sh**
service — not the in-cluster ntfy, which is one of the things that would be down.

| Failure | Caught? |
|---------|---------|
| Monitoring pods / their node down | yes — Watchdog pings stop |
| k3s-server1 or the whole cluster down | yes |
| A backup job fails, hangs or stops being scheduled | yes — `/fail` ping, or no ping within the grace time |
| `homelab1` or the Healthchecks container down | yes, the other way round — Prometheus scrapes it (`DeadmanWatcherDown`) |
| Power cut, router or internet down at home | **no** — watcher and ntfy.sh path die with it. Accepted; only an off-site watcher covers this |
| Cluster *and* `homelab1` down together | no |

## Files

```
monitoring/deadman/
├── docker-compose.yml       # Healthchecks on homelab1 (Compose / Arcane)
├── .env.example             # its configuration; the real .env is never committed
├── secrets-template.yaml    # the three Kubernetes Secrets holding ping URLs + API key
└── scrape-and-alerts.yaml   # ScrapeConfig + PrometheusRule: the cluster watches the watcher
```

Cluster-side wiring lives with what it configures: the `deadman` receiver and
Watchdog route in `monitoring/values.yaml`, the `HC_URL` pings in both
`backup/exoscale-s3/` CronJobs.

## Checks

| Check | Pinged by | Schedule in Healthchecks | Grace |
|-------|-----------|--------------------------|-------|
| `cluster-watchdog` | Alertmanager, every 1–2 min (always-firing `Watchdog` alert) | simple, period 2 min | 5 min |
| `exoscale-data` | `exoscale-s3-backup` CronJob: `/start`, then exit status | cron `0 2 * * *`, Europe/Brussels | 2 h |
| `exoscale-cluster` | `exoscale-s3-cluster-backup` CronJob: `/start`, then exit status | cron `30 3 * * *`, Europe/Brussels | 1 h |
| `etcd-snapshot-sync` | systemd unit on k3s-server1 (`ExecStartPost`) | cron `0 4 * * *`, UTC | 1 h |

Each check's time zone must match its sender: the CronJobs set
`timeZone: Europe/Brussels`, the etcd timer uses `OnCalendar=… UTC`.

Ping URLs are credentials (anyone on the LAN holding one can fake "alive"), so
they live in Secrets and in a root-only systemd drop-in — never in Git.
Healthchecks keeps the last 100 pings per check, so its database stays small.

## Install

### 1. Healthchecks on homelab1

```fish
# on homelab1, in the stack directory (or create the stack in Arcane from these two files)
cp .env.example .env
openssl rand -hex 32            # -> SECRET_KEY in .env
docker compose up -d
docker compose exec healthchecks /opt/healthchecks/manage.py createsuperuser
```

Open `http://10.0.0.50:8000`, then:

1. **Integrations → ntfy**: server `https://ntfy.sh`, topic = a long random
   string (`openssl rand -hex 16`; the topic name is the only secret on
   ntfy.sh), priority **5** for down and 3 for up. Subscribe to that topic in
   the ntfy phone app (add it under server `https://ntfy.sh`). Press *Test*.
2. Create the four checks from the table above, all using that integration.
3. **Project Settings → API Access**: create a **read-only** key; note the
   project UUID from the browser's address bar.

Leave it like this for ten minutes before going on: `cluster-watchdog` has never
been pinged, goes *down* after its grace time, and the phone must ring. That is
the end-to-end test of the alert path, for free.

### 2. Secrets — before anything that references them

Alertmanager mounts `deadman-heartbeat`; if it does not exist when the chart is
upgraded, the Alertmanager pod cannot start. Create all three first (commands
at the top of `secrets-template.yaml`).

### 3. Cluster side

```fish
# Watchdog -> Healthchecks (diff first; same flags as every kube-prometheus-stack upgrade)
helm diff upgrade prometheus prometheus-community/kube-prometheus-stack -n monitoring \
  -f monitoring/values.yaml \
  --set-file grafana.dashboards.homelab.backup-overview.json=monitoring/dashboards/backup-overview.json \
  --version 87.17.0
# ...then the same command with `upgrade` instead of `diff upgrade`.

# The cluster watches the watcher (metricsPath carries the Healthchecks project UUID;
# update it if the project is ever recreated)
kubectl apply -f monitoring/deadman/scrape-and-alerts.yaml

# Backup jobs start pinging on their next run
kubectl apply -f backup/exoscale-s3/cronjob.yaml -f backup/exoscale-s3/cronjob-cluster.yaml
```

### 4. etcd snapshot sync on k3s-server1

```bash
sudo systemctl edit etcd-snapshot-sync.service
# [Service]
# ExecStartPost=-/usr/bin/curl -fsS -m 10 --retry 3 -o /dev/null http://10.0.0.50:8000/ping/<uuid>
sudo chmod 600 /etc/systemd/system/etcd-snapshot-sync.service.d/override.conf
```

`ExecStartPost` only runs when the rsync succeeded, so a failed sync shows up as
a missing ping. The leading `-` keeps an unreachable watcher from marking the
sync itself failed.

## Verify

- `cluster-watchdog` turns green within two minutes of the Helm upgrade and
  shows a ping every minute.
- `kubectl -n backup create job hc-test --from=cronjob/exoscale-s3-cluster-backup`
  → the check shows *started*, then a success ping with the run time.
- Prometheus: `up{job="healthchecks"} == 1` and one `hc_check_up` series per check.
- Drill: silence `alertname="Watchdog"` in Alertmanager for 10 minutes. A
  silence stops the webhook too, so the pings stop, `cluster-watchdog` goes down
  after its grace time and the phone rings; when the silence expires the check
  recovers by itself. Nothing else is affected.
