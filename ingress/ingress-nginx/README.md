# ingress-nginx - Kubernetes Ingress Controller

## Overview

The ingress-nginx controller is an Ingress controller for Kubernetes using NGINX as a reverse proxy and load balancer. It handles external HTTP/HTTPS traffic routing to services within your cluster.

**Key features:**
- Production-ready ingress controller
- SSL/TLS termination
- Path-based and host-based routing
- WebSocket support
- Load balancing across pods
- Integration with cert-manager for automatic TLS

## Prerequisites

- Kubernetes cluster
- MetalLB or another LoadBalancer provider configured
- kubectl configured to access your cluster
- Helm 3.x installed

## Installation

### Step 1: Add Helm Repository

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
```

### Step 2: Install ingress-nginx

```bash
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --version 4.12.0 \
  -f custom-values.yaml
```

### Step 3: Verify Installation

```bash
# Check pod status
kubectl get pods -n ingress-nginx

# Check service (should show EXTERNAL-IP from MetalLB)
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Wait for controller to be ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

You should see an EXTERNAL-IP assigned by MetalLB (e.g., 192.168.1.100).

## Configuration

### Important Settings in custom-values.yaml

#### 1. allowSnippetAnnotations (Security)

```yaml
allowSnippetAnnotations: true
```

**⚠️ Security Warning:** Snippet annotations allow users to inject arbitrary NGINX configuration via annotations like `nginx.ingress.kubernetes.io/server-snippet`. This is **required for Nextcloud** and some other applications but poses a security risk.

**Recommendation:**
- Keep `true` if you need Nextcloud or similar apps requiring custom NGINX config
- Set to `false` if you don't need snippet annotations (more secure)
- Use RBAC to restrict who can create Ingress resources

#### 2. annotations-risk-level

```yaml
config:
  annotations-risk-level: Critical
```

Since ingress-nginx v1.12.0, this setting is required when using `allowSnippetAnnotations: true`. It acknowledges the security risk of allowing snippet annotations.

#### 3. externalTrafficPolicy

```yaml
service:
  externalTrafficPolicy: "Local"
```

**Benefits:**
- Preserves client source IP addresses (important for logging, rate limiting)
- Reduces network hops

**Trade-offs:**
- Traffic only routed to nodes where ingress pods are running
- May cause uneven load distribution if pods aren't on all nodes

**Alternative:** Set to `"Cluster"` for better load distribution at the cost of losing source IP.

## Usage

### Basic Ingress Example

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-app
  namespace: default
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - app.yourdomain.com
    secretName: example-app-tls
  rules:
  - host: app.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: example-app
            port:
              number: 80
```

Apply with:
```bash
kubectl apply -f ingress.yaml
```

### Common Annotations

```yaml
metadata:
  annotations:
    # Force HTTPS redirect
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"

    # Request body size limit (useful for file uploads)
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"

    # Timeouts for long-running requests
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"

    # Rate limiting
    nginx.ingress.kubernetes.io/limit-rps: "10"
```

## Troubleshooting

### 1. EXTERNAL-IP Stuck in `<pending>`

**Symptom:**
```bash
kubectl get svc -n ingress-nginx
# Shows <pending> instead of IP address
```

**Cause:** MetalLB not installed or not configured

**Solution:**
```bash
# Check MetalLB is running
kubectl get pods -n metallb-system

# Check MetalLB IPAddressPool configuration
kubectl get ipaddresspool -n metallb-system -o yaml
```

### 2. 502 Bad Gateway Errors

**Causes:**
- Backend pod not ready
- Service selector mismatch
- Network policy blocking traffic

**Debug:**
```bash
# Check backend pod status
kubectl get pods -n <namespace>

# Check service endpoints
kubectl get endpoints -n <namespace> <service-name>

# Check ingress-nginx logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
```

### 3. Source IP Lost (All Requests Show Internal IPs)

**Cause:** `externalTrafficPolicy` not set to "Local"

**Solution:** Verify in custom-values.yaml and upgrade:
```bash
helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --version 4.12.0 \
  -f custom-values.yaml
```

### 4. Snippet Annotations Not Working

**Symptom:** Annotations like `server-snippet` are ignored

**Cause:** `allowSnippetAnnotations: false` or missing `annotations-risk-level`

**Solution:** Update custom-values.yaml and upgrade Helm release

### 5. SSL/TLS Certificate Issues

**Debug:**
```bash
# Check certificate secret
kubectl get secret -n <namespace> <tls-secret-name>

# Describe certificate (if using cert-manager)
kubectl describe certificate -n <namespace> <cert-name>

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager
```

## Upgrading

### Check for Breaking Changes

Before upgrading, review the [ingress-nginx changelog](https://github.com/kubernetes/ingress-nginx/releases).

### Upgrade Helm Release

```bash
# Update repo
helm repo update

# Check new chart version
helm search repo ingress-nginx/ingress-nginx

# Upgrade to new version
helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --version <NEW_VERSION> \
  -f custom-values.yaml

# Verify
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx
```

## Integration with MetalLB

ingress-nginx creates a LoadBalancer service that requires MetalLB (or another LoadBalancer provider) to assign an external IP.

**MetalLB Configuration Example:**

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.100-192.168.1.110

---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
```

The ingress-nginx controller service will receive the first available IP from this pool.

## Migration from k3s-ansible

- **Source:** `roles/kubernetes/ingress_nginx/`
- **Chart version:** v4.12.0 (unchanged)
- **Variables converted:**
  - `ingress_nginx_enabled` → Removed (deployment is manual)
  - `ingress_nginx_namespace` → Documented as `ingress-nginx`
  - `ingress_nginx_chart_version` → Documented in README

### Changes from Ansible Deployment

1. **Namespace:** Still uses `ingress-nginx` namespace
2. **Values:** No changes to actual Helm values
3. **Deployment:** Manual Helm install instead of Ansible automation

## Additional Resources

- [Official Documentation](https://kubernetes.github.io/ingress-nginx/)
- [Helm Chart Repository](https://github.com/kubernetes/ingress-nginx/tree/main/charts/ingress-nginx)
- [Annotation Reference](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/)
- [TLS/HTTPS Guide](https://kubernetes.github.io/ingress-nginx/user-guide/tls/)
