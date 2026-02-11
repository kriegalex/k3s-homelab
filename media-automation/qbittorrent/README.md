# QBittorrent Chart

A Helm chart for deploying a QBittorrent client that uses a VPN tunnel provided by PIA.

## Persistent Storage

Create the PersistentVolumeClaim:

```bash
kubectl apply -f qbittorrent-config-pvc.yaml
```

This creates a Longhorn-backed persistent volume with automatic replication and snapshot support.

## NFS Torrent Storage

Apply NFS volume for torrent downloads:

```fish
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/media-automation/qbittorrent/nfs/nfs-torrent.yaml
```

See [qBittorrent NFS README](nfs/README.md) for details.

## Prerequisites
Before deploying this chart, ensure your Kubernetes cluster meets the following requirements:

1. Kubernetes 1.19+ – This chart uses features that are supported on Kubernetes 1.19 and above.
3. Helm 3.0+ – Helm 3 is required to manage and deploy this chart.
3. WireGuard Kernel Module – WireGuard must be available on all nodes in your cluster.

## Installation

### Allow unsafe sysctl

You need to allow two unsafe sysctl to be set by this chart. Create a drop-in configuration file on each worker node that will run qBittorrent.

**On each target worker node:**

```console
sudo mkdir -p /etc/rancher/k3s/config.yaml.d
cat <<EOF | sudo tee /etc/rancher/k3s/config.yaml.d/qbittorrent.yaml
kubelet-arg:
  - allowed-unsafe-sysctls=net.ipv4.conf.all.src_valid_mark,net.ipv6.conf.all.disable_ipv6
EOF
```

Restart the K3s agent service:

```console
sudo systemctl restart k3s-node
```

### Persistence

If not using longhorn and storage classnames:

On the control plane:
```console
kubectl apply -f qbittorrent-config-pv.yaml
kubectl -n media apply -f qbittorrent-config-pvc.yaml
```

On the applicable worker nodes:
```console
sudo mkdir -p /mnt/qbittorrent/config
sudo chown 1000:1000 /mnt/qbittorrent/config
```

### Setup VPN Configuration

⚠️ **IMPORTANT:** VPN credentials and WireGuard configuration must be stored in Kubernetes secrets, not in values files.

#### Option 1: WireGuard Config Secret (Recommended for Proton)

1. **Follow [this guide](https://protonvpn.com/support/wireguard-configurations)** to obtain your WireGuard configuration.

2. **Create secret from template:**
```bash
cp secrets-template.yaml secrets.yaml
# Edit secrets.yaml and replace with your actual WireGuard config
```

3. **Apply the secret:**
```bash
kubectl create namespace media
kubectl apply -f secrets.yaml
```

**Alternative: Create from file directly**
```bash
# Download your wg0.conf from ProtonVPN
kubectl create secret generic qbittorrent-vpn-config \
  --from-file=wg0.conf=./path/to/your/wg0.conf \
  --namespace=media
```

#### Option 2: PIA Credentials Secret

If using PIA instead of Proton:
```bash
kubectl create secret generic vpn-pia-credentials \
  --from-literal=pia-user='YOUR_USERNAME' \
  --from-literal=pia-password='YOUR_PASSWORD' \
  --namespace=media
```

### Helm Installation

**Prerequisites:**
- VPN secret must be created (see above)
- custom-values.yaml must NOT contain inline VPN config

1. **Add the Helm chart repo:**

```bash
helm repo add k8s-charts https://kriegalex.github.io/k8s-charts/
helm repo update
```

2. **Inspect & modify the default values:**

```bash
helm show values k8s-charts/qbittorrent > custom-values.yaml
```

**Important:** Update `custom-values.yaml` to remove inline VPN config and use the secret instead:
```yaml
vpn:
  enabled: true
  provider: proton
  # DO NOT include config: here - use the secret
  # The chart should mount the secret automatically

# If chart supports configFromSecret:
  configFromSecret: qbittorrent-vpn-config
```

3. **Install the chart:**

```bash
helm upgrade --install qbittorrent k8s-charts/qbittorrent \
  --namespace media \
  --create-namespace \
  -f custom-values.yaml
```

**Note:** If the chart doesn't support mounting secrets directly, you may need to manually mount the secret as a volume in your custom-values.yaml.

## QBittorrent login

The login is `admin`. The password is visible in the logs of the qbittorent app the first time you start it:

```
kubectl logs qbit-qbittorrent-POD_NAME
```

Replace POD_NAME by the name of your pod (`kubectl get pods`).

## Port Forwarding

The port forwarding should be handled automatically by the docker image, if the correct environment variables have been set.

You can check it in the logs:

```console
kubectl logs qbit-qbittorrent-POD_NAME
```

Expected result:
```console
******** Information ********
To control qBittorrent, access the WebUI at: http://localhost:8080

[INF] [] [VPN] Forwarded port is [PORT].
[INF] [] [QBITTORRENT] Updated forwarded port to [PORT].
```