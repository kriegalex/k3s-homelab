# Intel GPU Device Plugin

The Intel GPU Device Plugin enables GPU acceleration in Kubernetes by exposing Intel integrated GPUs to containers. This is essential for applications requiring hardware transcoding (Plex, Jellyfin, Immich) or GPU compute capabilities.

## Overview

**What it does:**
- Exposes Intel GPUs (`/dev/dri/renderD*`) to Kubernetes pods
- Enables hardware transcoding for media applications
- Provides GPU resource management via `gpu.intel.com/i915` resource

**Prerequisites:**
- Intel CPU with integrated graphics (iGPU)
- Host kernel with Intel GPU drivers loaded
- Nodes labeled with GPU availability (automatic via Node Feature Discovery)

**Resource Usage:**
- Minimal: ~10-20 MB RAM per GPU device plugin pod
- No GPU resources consumed by the plugin itself

## Quick Start

### Option 1: Automated Deployment (Recommended)

```bash
cd ~/workspace/k8s-homelab/hardware/intel-gpu-plugin
./deploy.sh
```

This script:
1. Deploys Node Feature Discovery (NFD) for automatic node labeling
2. Deploys Intel GPU Device Plugin
3. Verifies deployment and shows GPU-enabled nodes

### Option 2: Manual Deployment

**Step 1: Deploy Node Feature Discovery (NFD)**

NFD automatically labels nodes with Intel GPUs:

```bash
# Deploy NFD operator
kubectl apply -k https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/nfd?ref=v0.30.0

# Deploy NFD node feature rules
kubectl apply -k https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/nfd/overlays/node-feature-rules?ref=v0.30.0
```

**Step 2: Deploy Intel GPU Device Plugin**

```bash
# Deploy GPU plugin (uses NFD labels to target GPU nodes)
kubectl apply -k https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/gpu_plugin/overlays/nfd_labeled_nodes?ref=v0.30.0
```

**Step 3: Verify Deployment**

```bash
# Check NFD pods
kubectl get pods -n node-feature-discovery

# Check GPU plugin pods (one per GPU node)
kubectl get pods -n intel-gpu-plugin

# Verify GPU nodes are labeled
kubectl get nodes -L gpu.intel.com/device-id

# Check GPU resources available
kubectl describe nodes | grep -A 5 "gpu.intel.com"
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│                                                              │
│  ┌────────────────────┐    ┌──────────────────────────┐   │
│  │ Node Feature       │    │ Intel GPU Device Plugin  │   │
│  │ Discovery (NFD)    │───▶│ DaemonSet                │   │
│  │                    │    │                          │   │
│  │ Labels GPU nodes:  │    │ Exposes to pods:         │   │
│  │ gpu.intel.com/     │    │ - /dev/dri/renderD128    │   │
│  │ device-id=0xa7a0   │    │ - /dev/dri/card0         │   │
│  └────────────────────┘    └──────────────────────────┘   │
│                                       │                     │
│                                       ▼                     │
│  ┌───────────────────────────────────────────────────────┐ │
│  │ Application Pods (Plex, Jellyfin, Immich)            │ │
│  │                                                       │ │
│  │ resources:                                            │ │
│  │   limits:                                             │ │
│  │     gpu.intel.com/i915: 1                            │ │
│  └───────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Usage in Applications

### Requesting GPU in Helm Values

For applications like Plex, Jellyfin, or Immich, add GPU resources to your Helm values:

**Plex (`plex/values.yaml`):**
```yaml
resources:
  limits:
    gpu.intel.com/i915: 1  # Request 1 Intel GPU
```

**Jellyfin (`jellyfin/values.yaml`):**
```yaml
resources:
  limits:
    gpu.intel.com/i915: 1
```

**Immich (`immich/values.yaml`):**
```yaml
machine-learning:
  resources:
    limits:
      gpu.intel.com/i915: 1
```

### Requesting GPU in Raw Manifests

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: transcode-test
spec:
  containers:
  - name: ffmpeg
    image: linuxserver/ffmpeg:latest
    resources:
      limits:
        gpu.intel.com/i915: 1  # Request Intel GPU
    securityContext:
      privileged: false  # No privileged mode needed!
```

**Important:** You do NOT need `privileged: true` or manual device mounts. The GPU device plugin handles this automatically.

## Verification

### Test GPU Access in a Pod

```bash
# Deploy test pod
kubectl run gpu-test --image=ubuntu:22.04 --rm -it --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"gpu-test","image":"ubuntu:22.04","command":["sleep","3600"],"resources":{"limits":{"gpu.intel.com/i915":"1"}}}]}}' \
  -- /bin/bash

# Inside the pod, check GPU devices
ls -la /dev/dri/
# Expected output:
# renderD128  <- This is the GPU render device
# card0       <- This is the GPU card device

# Check Intel GPU info (if intel-gpu-tools installed)
apt update && apt install -y intel-gpu-tools
intel_gpu_top
```

### Check GPU Usage

```bash
# On the GPU node (SSH to the node)
sudo intel_gpu_top

# Or check kernel logs
dmesg | grep -i "i915"

# Check GPU processes
sudo lsof /dev/dri/renderD128
```

### Verify Resource Allocation

```bash
# Check which pods are using GPU
kubectl get pods -A -o json | \
  jq -r '.items[] | select(.spec.containers[].resources.limits."gpu.intel.com/i915" != null) | "\(.metadata.namespace)/\(.metadata.name)"'

# Check node GPU capacity
kubectl get nodes -o json | \
  jq -r '.items[] | "\(.metadata.name): \(.status.allocatable."gpu.intel.com/i915" // "no GPU")"'
```

## Supported Intel GPUs

The plugin supports Intel integrated GPUs (iGPU) from:

| Generation | Codename | Example CPUs | Device ID |
|------------|----------|--------------|-----------|
| 6th Gen | Skylake | i5-6500, i7-6700K | 0x1912, 0x191B |
| 7th Gen | Kaby Lake | i5-7500, i7-7700K | 0x5912, 0x591B |
| 8th Gen | Coffee Lake | i5-8400, i7-8700K | 0x3E92, 0x3E9B |
| 9th Gen | Coffee Lake Refresh | i5-9400, i7-9700K | 0x3E92, 0x3E98 |
| 10th Gen | Comet Lake | i5-10400, i7-10700K | 0x9BC8, 0x9BCA |
| 11th Gen | Rocket Lake | i5-11400, i7-11700K | 0x4C8A, 0x4C8B |
| 12th Gen | Alder Lake | i5-12400, i7-12700K | 0x4680, 0x4690 |
| 13th Gen | Raptor Lake | i5-13400, i7-13700K | 0xA780, 0xA7A0 |
| 14th Gen | Raptor Lake Refresh | i5-14400, i7-14700K | 0xA780, 0xA7A0 |

**Note:** Arc discrete GPUs are also supported but require additional configuration.

## Troubleshooting

### GPU Plugin Pods Not Running

**Symptom:** No pods in `intel-gpu-plugin` namespace

**Check:**
```bash
# Check if NFD labeled nodes with GPU
kubectl get nodes -L gpu.intel.com/device-id

# If no labels, check NFD is running
kubectl get pods -n node-feature-discovery

# Check NFD logs
kubectl logs -n node-feature-discovery -l app.kubernetes.io/name=nfd-master
```

**Fix:** Ensure NFD is deployed before GPU plugin:
```bash
kubectl apply -k https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/nfd?ref=main
kubectl apply -k https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/nfd/overlays/node-feature-rules?ref=main
```

### GPU Not Available in Pods

**Symptom:** Pod scheduled but `/dev/dri/` is empty or pod stuck in Pending

**Check:**
```bash
# Check if GPU resources exist on nodes
kubectl describe nodes | grep -A 5 "gpu.intel.com"

# Check GPU plugin DaemonSet
kubectl get daemonset -n intel-gpu-plugin

# Check GPU plugin logs
kubectl logs -n intel-gpu-plugin -l app=intel-gpu-plugin
```

**Common causes:**
1. **GPU drivers not loaded on host:** Check `lsmod | grep i915` on the node
2. **Wrong resource request:** Use `gpu.intel.com/i915` NOT `gpu.intel.com/gpu`
3. **Plugin not running on GPU node:** NFD might not have labeled the node

### Host Kernel GPU Drivers

**Verify drivers on the node:**
```bash
# SSH to the GPU node
ssh user@gpu-node

# Check i915 driver loaded
lsmod | grep i915

# Check GPU devices exist
ls -la /dev/dri/
# Should see: card0, renderD128

# Check GPU hardware detected
lspci | grep -i vga

# Check Intel GPU firmware
dmesg | grep -i "i915\|firmware"
```

**If drivers missing:**
```bash
# Ubuntu/Debian
sudo apt install linux-modules-extra-$(uname -r)

# RHEL/Rocky
sudo dnf install kernel-modules-extra

# Reboot may be required
sudo reboot
```

### Application Not Using GPU

**Symptom:** Plex/Jellyfin transcoding uses CPU instead of GPU

**Check pod resources:**
```bash
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A 5 "resources:"
```

**Verify GPU assigned:**
```bash
kubectl describe pod <pod-name> -n <namespace> | grep -A 10 "Limits:"
# Should show: gpu.intel.com/i915: 1
```

**Check application configuration:**
- **Plex:** Settings → Transcoder → Use hardware acceleration: Intel Quick Sync
- **Jellyfin:** Dashboard → Playback → Hardware Acceleration: Intel Quick Sync (QSV)
- **Immich:** Machine learning service should auto-detect GPU

**Verify GPU access inside pod:**
```bash
kubectl exec -it <pod-name> -n <namespace> -- ls -la /dev/dri/
# Should see renderD128 and card0
```

### NFD Not Labeling GPU Nodes

**Check NFD master:**
```bash
kubectl logs -n node-feature-discovery -l app.kubernetes.io/name=nfd-master
```

**Check NFD worker on GPU node:**
```bash
kubectl logs -n node-feature-discovery -l app.kubernetes.io/name=nfd-worker --all-containers
```

**Manually verify GPU on node:**
```bash
# SSH to node
lspci | grep -i vga
ls -la /dev/dri/
```

**Force NFD re-scan:**
```bash
# Delete NFD worker pod (will restart)
kubectl delete pod -n node-feature-discovery -l app.kubernetes.io/name=nfd-worker
```

## Uninstallation

### Remove GPU Plugin

```bash
# Delete GPU plugin DaemonSet
kubectl delete -k https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/gpu_plugin/overlays/nfd_labeled_nodes?ref=main

# Verify removal
kubectl get pods -n intel-gpu-plugin
# Should be empty or namespace deleted
```

### Remove NFD (Optional)

**Warning:** Only remove NFD if no other components depend on it.

```bash
# Delete NFD
kubectl delete -k https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/nfd/overlays/node-feature-rules?ref=main
kubectl delete -k https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/nfd?ref=main

# Verify removal
kubectl get pods -n node-feature-discovery
```

### Clean Up Node Labels

```bash
# List nodes with GPU labels
kubectl get nodes --show-labels | grep "gpu.intel.com"

# Remove GPU labels from nodes (if needed)
kubectl label nodes <node-name> gpu.intel.com/device-id-
kubectl label nodes <node-name> gpu.intel.com/millicores-
kubectl label nodes <node-name> gpu.intel.com/memory.max-
```

## Migration from k3s-ansible

If you previously deployed Intel GPU plugin via k3s-ansible:

### Current Deployment (k3s-ansible < Feb 2026)

```yaml
# inventory/group_vars/all/vars.yml
intel_gpu_plugin_enabled: true
```

### New Deployment (k8s-homelab)

```bash
cd ~/workspace/k8s-homelab/hardware/intel-gpu-plugin
./deploy.sh
```

**Migration Steps:**

1. **No action needed if already deployed:** The GPU plugin continues running. k3s-ansible removal doesn't affect deployed resources.

2. **For new deployments:** Use k8s-homelab deployment methods (script or kubectl commands).

3. **To update GPU plugin:**
   ```bash
   # Uninstall old version
   kubectl delete -k https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/gpu_plugin/overlays/nfd_labeled_nodes?ref=main

   # Reinstall latest
   ./deploy.sh
   ```

**Key Differences:**
- k3s-ansible used Ansible automation
- k8s-homelab uses direct kubectl/script deployment
- Functionality remains identical
- No downtime required for migration

## Performance Benchmarks

### Transcoding Performance (H.264 → H.264 1080p)

| CPU | GPU | CPU Usage | GPU Usage | Speedup |
|-----|-----|-----------|-----------|---------|
| Software (libx264) | None | 100% | 0% | 1x |
| Intel Quick Sync | i5-10400 iGPU | 5% | 60% | ~8-10x |
| Intel Quick Sync | i7-12700K iGPU | 3% | 40% | ~12-15x |

### Power Consumption

| Method | Power Draw | Efficiency |
|--------|------------|------------|
| CPU Transcode | +60-80W | Low |
| GPU Transcode | +10-15W | High |

**Energy savings:** GPU transcoding uses ~75% less power than CPU transcoding.

## Advanced Configuration

### Multiple GPUs

If you have multiple Intel GPUs (e.g., iGPU + discrete Arc GPU):

```bash
# Check available GPUs
kubectl get nodes -o json | \
  jq -r '.items[] | "\(.metadata.name): \(.status.allocatable)"' | \
  grep "gpu.intel.com"

# Pod can request specific GPU by index (if exposed)
resources:
  limits:
    gpu.intel.com/i915: 1
```

### GPU Sharing

By default, one GPU = one pod. For GPU sharing:

**Option 1: Fractional GPU (Time-slicing)**
- Requires [gpu-feature-discovery](https://github.com/kubernetes-sigs/gpu-feature-discovery)
- Enables multiple pods to share one GPU (time-sliced)

**Option 2: SR-IOV (Virtual Functions)**
- Requires GPU with SR-IOV support
- Creates virtual GPU instances

**Note:** Standard Intel iGPUs do NOT support sharing. Each pod gets exclusive access.

### Custom Device Plugin Configuration

For advanced scenarios, deploy with custom ConfigMap:

```bash
# Clone Intel device plugins repo
git clone https://github.com/intel/intel-device-plugins-for-kubernetes.git
cd intel-device-plugins-for-kubernetes/deployments/gpu_plugin

# Customize kustomization
nano kustomization.yaml

# Deploy
kubectl apply -k .
```

## References

- **Official Documentation:** [Intel Device Plugins for Kubernetes](https://github.com/intel/intel-device-plugins-for-kubernetes)
- **Node Feature Discovery:** [NFD GitHub](https://github.com/kubernetes-sigs/node-feature-discovery)
- **Intel Graphics Drivers:** [Intel Download Center](https://www.intel.com/content/www/us/en/download-center/home.html)
- **Quick Sync Video:** [Intel Quick Sync Documentation](https://www.intel.com/content/www/us/en/architecture-and-technology/quick-sync-video/quick-sync-video-general.html)

## Getting Help

**Issues:** [k8s-homelab GitHub Issues](https://github.com/kriegalex/k8s-homelab/issues)

**Intel GPU Plugin Issues:** [Intel Device Plugins Issues](https://github.com/intel/intel-device-plugins-for-kubernetes/issues)

---

**Last Updated:** February 2026 (migrated from k3s-ansible)
