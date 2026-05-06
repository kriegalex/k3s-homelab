# Clonarr

[Clonarr](https://github.com/prophetse7en/clonarr) — visual TRaSH-Guides sync
tool for Radarr and Sonarr (Custom Formats, Quality Profiles, Scores, Quality
Sizes), web UI in place of YAML.

> **Pick one.** Clonarr, Recyclarr, and Configarr all sync TRaSH content into
> the same instances. Running two of them will cause CFs to ping-pong as each
> prunes the other's. Stick to a single sync tool per Radarr/Sonarr instance.

## Persistent Storage

Create the PersistentVolumeClaim (Longhorn-backed):

```bash
kubectl apply -f clonarr-pvc.yaml
```

## Add repository

The chart lives in the home-lab `k8s-charts` repo (published once the chart
hits `main`):

```bash
helm repo add k8s-charts https://kriegalex.github.io/k8s-charts/
helm repo update
```

If the chart hasn't been published yet, install directly from the local
checkout:

```bash
helm dependency update ~/workspace/k8s-charts/charts/clonarr
helm upgrade --install clonarr ~/workspace/k8s-charts/charts/clonarr \
  --namespace media --create-namespace -f values.yaml
```

## Install chart

```bash
helm upgrade --install clonarr k8s-charts/clonarr \
  --namespace media --create-namespace \
  -f values.yaml
```

## First-time setup

1. Browse to <http://clonarr.k3s.home> (or `kubectl -n media port-forward svc/clonarr 6060:80`).
2. Walk through the `/setup` flow to create the admin account.
3. Settings → add your Radarr and Sonarr (TV + anime) instances. URLs follow
   the in-cluster service names (e.g. `http://radarr.media.svc.cluster.local`)
   and the API keys come from each Arr's Settings → General.
4. Settings → Trusted Networks: lock down to the homelab subnet if you don't
   want the UI exposed to the rest of the LAN.

## Default values

```bash
helm show values k8s-charts/clonarr > clonarr-defaults.yaml
```

The chart wraps `bjw-s/app-template`, so all upstream knobs are available
under the `app-template:` key. See
<https://bjw-s-labs.github.io/helm-charts/docs/app-template/> for the full
schema.

## Files

- `clonarr-pvc.yaml` — 2Gi Longhorn PVC for `/config` (history, profile cache).
- `values.yaml` — version-controlled deploy values (image, env, ingress, affinity).
- `helm-values.yaml` — *auto-generated post-deploy* via `helm get values clonarr -n media`. Do not commit; not the source of truth.
