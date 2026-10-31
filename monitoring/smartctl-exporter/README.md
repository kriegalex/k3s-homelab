# smartctl-exporter

S.M.A.R.T. metrics for the nodes' system NVMe (`/dev/nvme0n1` on all four nodes), scraped by the
kube-prometheus-stack Prometheus. Alert rules are in `values.yaml` (`prometheusRules.rules`).

**Chart:** `prometheus-community/prometheus-smartctl-exporter` **0.19.0** (exporter v0.15.0)
**Release / namespace:** `smartctl-exporter` / `monitoring`

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community

helm diff upgrade --install smartctl-exporter prometheus-community/prometheus-smartctl-exporter \
  -n monitoring --version 0.19.0 -f monitoring/smartctl-exporter/values.yaml
helm upgrade --install smartctl-exporter prometheus-community/prometheus-smartctl-exporter \
  -n monitoring --version 0.19.0 -f monitoring/smartctl-exporter/values.yaml
```

Verify: `kubectl -n monitoring get ds -l app.kubernetes.io/name=prometheus-smartctl-exporter` shows 4/4,
and in Prometheus `smartctl_device_smart_status` returns one series per node with value 1.

The DaemonSet is privileged (raw device access for `smartctl`) and mounts the host `/dev`. The chart
scans all block devices by default; `values.yaml` pins it to the NVMe because the workers' Longhorn
iSCSI disks would otherwise be probed on every cycle.

Companion Grafana dashboard: `smartctl-exporter` (grafana.com 22604) is loaded through the
kube-prometheus-stack `values.yaml` dashboards list.
