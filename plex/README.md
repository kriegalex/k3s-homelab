# Plex

## Worker node installation

### Basic installation

Follow the main [INSTALL.md](../INSTALL.md) to install a worker node.

Then, instead of using `kubeadm init`, you use the `kubeadm join` command that was created during the install of the control plane. 

### (optional) Recreate a token

If you forgot the join command, or if the token expired, you can recreate a token. An expired token will result in the `kubeadm join` command to appear as stuck. You can check what is going on by adding `--v=2` at the end of the command:

```
sudo kubeadm join 10.0.0.10:6443 --token TOKEN --discovery-token-ca-cert-hash SHA --v=2
```

An expired token may give the following error:

> Retrying due to error: could not find a JWS signature in the cluster-info ConfigMap for token ID "TOKEN"

To recreate a new `kubeadm join` command, use:

```
# On the control plane node
kubeadm token create --print-join-command
```

### Label the worker node

```
kubectl label node WORKER-NODE-NAME node-role.kubernetes.io/worker=worker
```

### Enable hardware transcoding for an Intel ARC GPU

> **IMPORTANT**
>
> As of August 2024, only Plex server v1.40.1 works with both hardware transcoding and tone mapping enabled with an Intel ARC GPU. Mine is a A380 and I am running Ubuntu 22.04.4 LTS with HWE 6.5.0 kernel. Intel GPU plugin is v0.30.0 for kubernetes v1.30.

#### Render group

Add your user to the render group:

```console
sudo usermod -a -G render $USER
```

> Note: if it is not the current $USER that will run the container, please adapt the command accordingly.

#### Drivers
If you are on Ubuntu 22.04 LTS, or on a modern Linux distribution with access to kernel >=6.2, the drivers for an Intel ARC GPU should already be working. More details [here](https://dgpu-docs.intel.com/driver/installation.html#ubuntu-install-steps). On Ubuntu 22.04.3 LTS, the kernel 6.5 is easily available with the [HWE kernel](https://askubuntu.com/questions/1442208/how-to-enable-hwe-on-ubuntu-22-04).

You can check the state of the drivers and of the GPU using HWInfo:
```
sudo apt install hwinfo
hwinfo --display
```

Note the i915 driver and its "active" status:
```
 Driver: "i915"
  Driver Modules: "i915"
  Memory Range: 0xfb000000-0xfbffffff (rw,non-prefetchable)
  Memory Range: 0xb0000000-0xbfffffff (ro,non-prefetchable)
  Memory Range: 0xfc000000-0xfc1fffff (ro,non-prefetchable,disabled)
  IRQ: 94 (96 events)
  Module Alias: "pci:v00008086d000056A6sv00001849sd00006007bc03sc00i00"
  Driver Info #0:
    Driver Status: i915 is active
```

#### Intel OpenCL ICD

To test that OpenCL is working on the node, please install the intel runtime and run clinfo:

```
sudo apt install intel-opencl-icd clinfo
sudo clinfo -l
```

The output for my Intel ARC A310 (please note the ID [0x56a6](https://dgpu-docs.intel.com/devices/hardware-table.html)):
```
Platform #0: Intel(R) OpenCL HD Graphics
 `-- Device #0: Intel(R) Graphics [0x56a6]
```

#### Kernel parameters

If you use the HWE kernel from Ubuntu 22.04.4 LTS, you have a 6.5.0+ kernel. This version should normally support an Intel ARC A310/A380 GPU out of the box. You should NOT need to modify anything more.

##### (optional) Enable GuC

Use this command to activate GuC in the kernel config:

```
echo "options i915 enable_guc=2" | sudo tee /etc/modprobe.d/i915.conf
sudo update-initramfs -u
```

##### (optional) GRUB changes for i915

First, identify which GPU ID is right for you using the Intel Hardware Table. In my case, it is 56a5 for an ARC A380.

Then, we will add some default parameters to GRUB bootloader:
```
sudo nano /etc/default/grub
```

On Ubuntu 22.04.3 LTS, my GRUB_CMDLINE_LINUX_DEFAULT was empty. I modified it with:

```
GRUB_CMDLINE_LINUX_DEFAULT="i915.enable_hangcheck=0 pci=realloc=off i915.force_probe=56a5"
```

Please note the use of my GPU ID in `i915.force_probe=`.

**Reboot:**

```
sudo update-grub
sudo reboot
```

#### GPU Plugin installation (no helm)

```console
# Start NFD - if your cluster doesn't have NFD installed yet
kubectl apply -k 'https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/nfd?ref=v0.30.0'

# Create NodeFeatureRules for detecting GPUs on nodes
kubectl apply -k 'https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/nfd/overlays/node-feature-rules?ref=v0.30.0'

# Create GPU plugin daemonset
kubectl apply -k 'https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/gpu_plugin/overlays/nfd_labeled_nodes?ref=v0.30.0'
```

#### GPU Plugin installation (with helm)

> This method is not 100% sure to work

Intel GPU helm charts also depends on cert-manager, this guide assumes you installed it already by following the [ingress README](../ingress/README.md). Original instructions by Intel [here](https://github.com/intel/intel-device-plugins-for-kubernetes/blob/main/INSTALL.md).

```
helm repo add nfd https://kubernetes-sigs.github.io/node-feature-discovery/charts # for NFD
helm repo add intel https://intel.github.io/helm-charts/ # for device-plugin-operator and plugins
helm repo update
```

##### NFD

Deploy GPU plugin with the help of NFD (Node Feature Discovery). It detects the presence of Intel GPUs and labels them accordingly. GPU plugin’s node selector is used to deploy plugin to nodes which have such a GPU label.

```
helm repo add nfd https://kubernetes-sigs.github.io/node-feature-discovery/charts 
helm install nfd nfd/node-feature-discovery \
  --namespace node-feature-discovery --create-namespace
```

##### Operator

```
helm repo add intel https://intel.github.io/helm-charts/
helm install dp-operator intel/intel-device-plugins-operator --namespace inteldeviceplugins-system --create-namespace
```

##### GPU Plugin

```
helm install intel-device-plugins-gpu intel/intel-device-plugins-gpu \
  --namespace inteldeviceplugins-system --create-namespace \
  --set nodeFeatureRule=true
```

You can verify that the plugin has been installed on the expected nodes by searching for the relevant resource allocation status on the nodes:
```
kubectl get nodes -o=jsonpath="{range .items[*]}{.metadata.name}{'\n'}{' i915: '}{.status.allocatable.gpu\.intel\.com/i915}{'\n'}"
```

#### Check the node label

**(IMPORTANT) Check the label of this ARC gpu for pod affinity:**

```
kubectl describe node plex
```

Output example:
```
Labels:             beta.kubernetes.io/arch=amd64
                    beta.kubernetes.io/os=linux
                    gpu.intel.com/device-id.0300-56a5.count=1
                    gpu.intel.com/device-id.0300-56a5.present=true
                    gpu.intel.com/family=A_Series
                    intel.feature.node.kubernetes.io/gpu=true
                    kubernetes.io/arch=amd64
                    kubernetes.io/hostname=plex
                    kubernetes.io/os=linux
```

We want to know the ID of our GPU, in this example `0300-56a5`. This will be useful for the [custom values](./plex/custom-values.yaml) during the [Plex installation](./plex/README.md).

#### Verify the cluster plugin

Follow [these instructions](https://intel.github.io/intel-device-plugins-for-kubernetes/cmd/gpu_plugin/README.html#testing-and-demos) to run a docker image inside your cluster that will test that the Intel GPU is working as intended.

You need to [install Docker](https://docs.docker.com/engine/install/) and the `make` tools for your OS (`apt install build-essential` on Ubuntu/Debian).

## Persistent Storage

Create the PersistentVolumeClaim:

```bash
kubectl apply -f pms-config-pvc.yaml
```

This creates a Longhorn-backed persistent volume with automatic replication and snapshot support.

## NFS Media Libraries

Plex requires namespace-specific NFS PVCs for media libraries. Apply these before deploying Plex:

```fish
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/plex/nfs/nfs-movies-plex.yaml
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/plex/nfs/nfs-tv-plex.yaml
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/plex/nfs/nfs-anime-plex.yaml
kubectl apply -f /home/mlourenco/workspace/k3s-homelab/plex/nfs/nfs-music-plex.yaml
```

These PVCs reference the same NFS paths as the base media libraries but are created in the `plex` namespace (Kubernetes PVCs cannot be shared across namespaces).

See [Plex NFS Guide](nfs/README.md) for details.

## Plex installation

1. Add the Plex helm repo:
```
helm repo add plex https://raw.githubusercontent.com/plexinc/pms-docker/gh-pages
```

2. Inspect and modify the default values:

```
helm show values plex/plex-media-server > custom-values.yaml
```

You can check an [example here](./custom-values.yaml).

3. Create the pms-config [PersistentVolume](./plex-pv.yaml):

```
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pms-config
spec:
  accessModes:
  - ReadWriteOnce
  capacity:
    storage: 200Gi
  persistentVolumeReclaimPolicy: Retain
  storageClassName: fast-nvme # by default is "standard"
  hostPath:
    path: "/mnt/pms-config"
 ```
 
 ```
 kubectl apply -f plex-pv.yaml
 ```
 
 4. Install Plex

```
helm install plex-media-server plex/plex-media-server -f custom-values.yaml
```

If you want to import an existing library, don't setup the server yet. Otherwise, you can go ahead and start the setup.

The plex server should be reachable either via the Ingress you setup or via the `EXTERNAL-IP` the service obtained from the LoadBalancer:

Check the LoadBalancer IP:
```
kubectl get svc
```

Check the Ingress URL:
```
kubectl get ingress
```

Other scenarios are possible, but outside the scope of this guide.

### Import an existing library

If you used the script in the helm custom values, plex pod should be in an Init status:

```
NAME                                               READY   STATUS     RESTARTS   AGE
plex-media-server-0                                0/1     Init:0/1   0          55s
```

(optional) Backup the existing library:

```
tar -czvf pms.tgz Library
```

The "Library" folder should look like that inside: `Library/Application Support/Plex Media Server`.

Don't forget to stop the server before doing the backup. The location of the library depends on the [type of server you are running](https://support.plex.tv/articles/202915258-where-is-the-plex-media-server-data-directory-located/). If you are running docker, the path is setup in the docker-compose file or in the Dockerfile.

In the custom values, you can enable the script that will wait for you to copy an archive named `pms.tgz`. First, copy it to the pod using a different name:

```
kubectl cp pms.tgz plex-media-server-0:/pms.tgz.up -c plex-media-server-pms-init
```

Then, move it so it has the proper name:

```
kubectl exec --stdin --tty plex-media-server-0 -c plex-media-server-pms-init h -- mv /pms.tgz.up /pms.tgz
```

As soon, as you move it, the script should start processing it.

#### I/O timeout error

If you have an "i/o timeout" error while using `kubectl cp`, consider copying the archive directly onto the plex worker node.

From the worker node:

```
# adapt it if you modified the PersistentVolume for plex
cd /mnt/pms-config
sudo scp user@IP:/mnt/user/backup/plex/pms.tgz .
```

From the control plane:

```
kubectl exec --stdin --tty plex-media-server-0 -c plex-media-server-pms-init h -- mv /config/pms.tgz /pms.tgz
```

## Plex configuration

### Custom URL

If you have a kubernetes cluster with nginx as ingress (or another ingress), as well as cert-manager (see [here](../ingress/README.md)), you can setup a custom URL for Plex instead of relying on the traditional forwarding of port 32400.

In that case, the plex service doesn't need to be of type LoadBalancer, and you can enable the ingress portion of the plex helm configuration.

Don't forget to setup the plex server with the custom URL under `Settings > Server > Network > Custom server access URLs`:

```
https://plex.mycustomdomain.com:443
```