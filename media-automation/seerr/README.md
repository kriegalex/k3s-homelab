# Seerr

Migrated from Overseerr. Reuses the existing `overseerr-config` PVC — first start
auto-migrates the SQLite config DB in place (per the upstream migration guide).

## Persistent storage

The PVC manifest lives here as `overseerr-config-pvc.yaml`. The name is kept as
`overseerr-config` (not renamed to `seerr-config`) so the existing Longhorn
volume is reused and Seerr can auto-migrate the config DB in place on first
start.

```bash
kubectl apply -f overseerr-config-pvc.yaml
```

This is a no-op against the existing PVC — applying it just transfers ownership
of the manifest to this folder so `media-automation/overseerr/` can be deleted
once the migration is verified.

## Pre-flight

1. Take a Longhorn snapshot of the `overseerr-config` PVC as a rollback point.
2. Uninstall the old release: `helm uninstall overseerr -n media`
   (the PVC is applied separately and is retained.)

## Install

OCI chart, no `helm repo add` needed:

```bash
helm upgrade --install seerr \
  oci://ghcr.io/seerr-team/seerr/seerr-chart \
  -n media \
  -f values.yaml
```

## Default values reference

`values.yaml` in this folder is the upstream chart's default values, kept for
reference. Do not pass it to helm — pass `values.yaml`.

```bash
helm show values oci://ghcr.io/seerr-team/seerr/seerr-chart > values.yaml
```

## Notes

- Pinned to `v3.2.0`; bump deliberately rather than tracking `latest`.
- Chart runs as UID/GID 1000 with `fsGroup: 1000` and
  `fsGroupChangePolicy: OnRootMismatch`, so the existing PVC contents will be
  chowned automatically on first mount.
- Ingress host kept as `overseerr.lourenco.ch` to avoid breaking bookmarks and
  Plex/Sonarr/Radarr integrations. TLS secret renamed to `seerr-tls`
  (cert-manager will issue a fresh cert on first reconcile).
