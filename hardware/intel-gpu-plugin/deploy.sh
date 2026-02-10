#!/bin/bash
set -e

# Intel GPU Device Plugin Deployment Script
# This script deploys Node Feature Discovery (NFD) and Intel GPU Device Plugin

# Version of Intel Device Plugins to deploy
VERSION="${INTEL_DEVICE_PLUGINS_VERSION:-v0.30.0}"

echo "=========================================="
echo "Intel GPU Device Plugin Deployment"
echo "=========================================="
echo ""
echo "Using Intel Device Plugins version: ${VERSION}"
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl not found. Please install kubectl first.${NC}"
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster. Check your kubeconfig.${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Kubernetes cluster accessible"
echo ""

# Step 1: Deploy Node Feature Discovery (NFD)
echo "=========================================="
echo "Step 1: Deploying Node Feature Discovery"
echo "=========================================="
echo ""
echo "NFD automatically labels nodes with Intel GPUs..."
echo ""

if kubectl get namespace node-feature-discovery &> /dev/null; then
    echo -e "${YELLOW}⚠${NC} NFD namespace already exists. Skipping NFD deployment."
else
    echo "Deploying NFD operator..."
    kubectl apply -k https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/nfd?ref=${VERSION}

    echo ""
    echo "Waiting for NFD to be ready..."
    kubectl wait --for=condition=available --timeout=120s deployment/nfd-master -n node-feature-discovery 2>/dev/null || true
    sleep 10

    echo ""
    echo "Deploying NFD node feature rules..."
    kubectl apply -k https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/nfd/overlays/node-feature-rules?ref=${VERSION}

    echo ""
    echo "Waiting for NFD to label nodes (this may take 30-60 seconds)..."
    sleep 30
fi

echo -e "${GREEN}✓${NC} NFD deployed successfully"
echo ""

# Step 2: Verify GPU nodes are labeled
echo "=========================================="
echo "Step 2: Verifying GPU Node Labels"
echo "=========================================="
echo ""

GPU_NODES=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.labels."gpu.intel.com/device-id" != null) | .metadata.name' 2>/dev/null)

if [ -z "$GPU_NODES" ]; then
    echo -e "${YELLOW}⚠${NC} No GPU nodes detected yet. This could mean:"
    echo "  1. NFD is still scanning nodes (wait 1-2 minutes)"
    echo "  2. No Intel GPUs present on cluster nodes"
    echo "  3. Intel GPU drivers not loaded on host nodes"
    echo ""
    echo "To check manually after deployment:"
    echo "  kubectl get nodes -L gpu.intel.com/device-id"
    echo ""
    read -p "Continue with GPU plugin deployment anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled."
        exit 1
    fi
else
    echo -e "${GREEN}✓${NC} Found GPU-enabled nodes:"
    echo "$GPU_NODES" | while read node; do
        DEVICE_ID=$(kubectl get node $node -o jsonpath='{.metadata.labels.gpu\.intel\.com/device-id}')
        echo "  - $node (GPU Device ID: $DEVICE_ID)"
    done
fi

echo ""

# Step 3: Deploy Intel GPU Device Plugin
echo "=========================================="
echo "Step 3: Deploying Intel GPU Device Plugin"
echo "=========================================="
echo ""

if kubectl get namespace intel-gpu-plugin &> /dev/null; then
    echo -e "${YELLOW}⚠${NC} Intel GPU plugin namespace already exists."
    read -p "Redeploy GPU plugin? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing old GPU plugin..."
        kubectl delete -k https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/gpu_plugin/overlays/nfd_labeled_nodes?ref=${VERSION} 2>/dev/null || true
        sleep 5
    else
        echo "Skipping GPU plugin deployment."
        GPU_PLUGIN_DEPLOYED=false
    fi
fi

if [ "${GPU_PLUGIN_DEPLOYED}" != "false" ]; then
    echo "Deploying Intel GPU Device Plugin..."
    kubectl apply -k https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/gpu_plugin/overlays/nfd_labeled_nodes?ref=${VERSION}

    echo ""
    echo "Waiting for GPU plugin DaemonSet to be ready..."
    kubectl wait --for=condition=ready --timeout=120s pod -l app=intel-gpu-plugin -n intel-gpu-plugin 2>/dev/null || true

    echo -e "${GREEN}✓${NC} Intel GPU Device Plugin deployed successfully"
fi

echo ""

# Step 4: Verification
echo "=========================================="
echo "Step 4: Deployment Verification"
echo "=========================================="
echo ""

echo "NFD Pods:"
kubectl get pods -n node-feature-discovery
echo ""

echo "GPU Plugin Pods:"
if kubectl get pods -n intel-gpu-plugin &> /dev/null; then
    kubectl get pods -n intel-gpu-plugin
else
    echo -e "${YELLOW}No GPU plugin pods found (normal if no GPU nodes detected)${NC}"
fi
echo ""

echo "GPU-Enabled Nodes:"
kubectl get nodes -L gpu.intel.com/device-id
echo ""

echo "GPU Resources Available:"
kubectl get nodes -o json | jq -r '.items[] | select(.status.allocatable."gpu.intel.com/i915" != null) | "\(.metadata.name): \(.status.allocatable."gpu.intel.com/i915") GPUs"' 2>/dev/null || echo -e "${YELLOW}No GPU resources found${NC}"
echo ""

# Summary
echo "=========================================="
echo "Deployment Summary"
echo "=========================================="
echo ""

if [ -n "$GPU_NODES" ] && kubectl get pods -n intel-gpu-plugin &> /dev/null; then
    echo -e "${GREEN}✓${NC} Deployment successful!"
    echo ""
    echo "Next steps:"
    echo "  1. Add GPU resources to your application Helm values:"
    echo "     resources:"
    echo "       limits:"
    echo "         gpu.intel.com/i915: 1"
    echo ""
    echo "  2. Verify GPU access in application pods:"
    echo "     kubectl exec -it <pod-name> -n <namespace> -- ls -la /dev/dri/"
    echo ""
    echo "  3. See README.md for application-specific configuration examples"
else
    echo -e "${YELLOW}⚠${NC} Deployment completed with warnings"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check if Intel GPU drivers are loaded on nodes:"
    echo "     ssh user@node-name 'lsmod | grep i915'"
    echo ""
    echo "  2. Check GPU devices exist on nodes:"
    echo "     ssh user@node-name 'ls -la /dev/dri/'"
    echo ""
    echo "  3. Wait 1-2 minutes for NFD to scan and label nodes"
    echo ""
    echo "  4. Check NFD logs:"
    echo "     kubectl logs -n node-feature-discovery -l app.kubernetes.io/name=nfd-master"
    echo ""
    echo "  5. See README.md for detailed troubleshooting guide"
fi

echo ""
echo "For more information, see: README.md"
echo ""
