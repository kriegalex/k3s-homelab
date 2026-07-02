# nfs-healer — Unraid NFS stale-handle auto-healer

Defense-in-depth safety net for `stale NFS file handle` errors on the
Unraid-backed shares of **immich**, **nextcloud**, and **paperless**.

## Why this exists

NFS file handles encode the underlying inode. On Unraid, when a file moves
between the cache pool and the array (mover), or when the server re-exports
(reboot / array stop-start), the handle a client holds can go **stale**
(`NFS: server ... error: fileid changed`). kubelet does **not** remount an NFS
volume on container restart — only on **pod recreation** — so the reliable
recovery is to delete the affected pod and let its controller recreate it with
a fresh mount.

The **root cause** is fixed server-side (see the plan
`Reliable fix for Unraid NFS stale file handles`):
- immich + paperless shares → **cache-only** (`Primary=cache, Secondary=None`)
- nextcloud share → **array-only** (`Primary=Array, Secondary=None`)

so the mover no longer changes inodes. This CronJob only catches the residual
cases (host reboots / re-exports). If it never fires, that's the expected
steady state.

## How it works

- Runs every 5 min (`concurrencyPolicy: Forbid`).
- Scans **Events** in the `immich`, `nextcloud`, `paperless` namespaces for
  messages containing `stale NFS file handle` (the signal kubelet emits on
  `FailedMount` / container-spec `Failed`). Detection is event-based on purpose:
  a fresh healer pod would get a fresh mount and never reproduce the app pod's
  stale handle, so mounting the shares as a probe would not work.
- **Health-gated**: only deletes a pod that has a *recent* (≤15 min) stale-handle
  event **and** is currently **not Ready**. A healthy `Ready=True` pod is never
  touched, even if an old event lingers.
- `kubectl delete pod` → the owning Deployment/StatefulSet recreates it → kubelet
  performs a fresh NFS mount.

## RBAC / blast radius

`ClusterRole` (get/list events; get/list/delete pods) bound via a **RoleBinding
in each of the three app namespaces only** — no ClusterRoleBinding — so the
healer can never delete pods anywhere else in the cluster.

## Files

| File | Contents |
|------|----------|
| `serviceaccount.yaml` | `nfs-healer` namespace + ServiceAccount |
| `rbac.yaml` | ClusterRole + 3 namespaced RoleBindings |
| `cronjob.yaml` | the `*/5` healer CronJob (image pinned to cluster kubectl version) |

## Deploy

```sh
kubectl apply -f storage/nfs-healer/serviceaccount.yaml
kubectl apply -f storage/nfs-healer/rbac.yaml
kubectl apply -f storage/nfs-healer/cronjob.yaml
```

## Test / operate

```sh
# one-off manual run
kubectl -n nfs-healer create job --from=cronjob/nfs-healer nfs-healer-manual
kubectl -n nfs-healer logs job/nfs-healer-manual

# on a healthy cluster the log ends with "nfs-healer sweep complete" and no DELETE lines
```

On cluster upgrade, bump the `image: alpine/k8s:<tag>` in `cronjob.yaml` to
match the new kube-apiserver minor version.
