# Prometheus Stack (kube-prometheus-stack) Installation Guide

This guide covers installation of the complete Prometheus monitoring stack including Grafana dashboards. The stack includes Prometheus, Alertmanager, Grafana, and Kubernetes-specific exporters and dashboards.

**Chart Version:** v63.1.0
**Repository:** https://prometheus-community.github.io/helm-charts
**Chart:** kube-prometheus-stack

## Table of Contents

- [Prerequisites](#prerequisites)
- [Setup Secrets](#setup-secrets)
- [Installation](#installation)
- [OAuth/SSO Configuration](#oauthsso-configuration-optional)
- [Accessing Grafana](#accessing-grafana)
- [Dashboards](#dashboards)
- [Troubleshooting](#troubleshooting)
- [Migration from k3s-ansible](#migration-from-k3s-ansible)

## Prerequisites

- A Kubernetes cluster up and running
- `kubectl` configured to access your cluster
- Helm 3 installed on your local machine
- Grafana admin credentials stored in Kubernetes secret (see below)

## Setup Secrets

⚠️ **IMPORTANT:** Grafana admin password must be stored in a Kubernetes secret.

### Create Secrets from Template

1. **Copy and edit the secrets template:**
```bash
cp secrets-template.yaml secrets.yaml
# Edit secrets.yaml and replace CHANGE_ME_GRAFANA_PASSWORD
```

2. **Generate secure password:**
```bash
openssl rand -base64 32
```

3. **Apply the secret:**
```bash
kubectl create namespace monitoring
kubectl apply -f secrets.yaml
```

### Alternative: Create Secret via Command Line

```bash
kubectl create namespace monitoring

kubectl create secret generic grafana-admin-credentials \
  --from-literal=admin-user='admin' \
  --from-literal=admin-password="$(openssl rand -base64 32)" \
  --namespace=monitoring
```

## Installation

### Step 1: Add Helm Repository

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

### Step 2: Deploy the kube-prometheus-stack

**Prerequisites:** Grafana admin secret must be created (see Setup Secrets above).

```bash
# Install the complete monitoring stack
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f custom-values.yaml \
  --version 63.1.0
```

### Step 3: Verify Installation

```bash
# Check all monitoring pods
kubectl get pods -n monitoring

# Expected pods:
# - prometheus-kube-prometheus-operator-xxx
# - prometheus-prometheus-kube-prometheus-prometheus-0
# - prometheus-grafana-xxx
# - prometheus-kube-state-metrics-xxx
# - alertmanager-prometheus-kube-prometheus-alertmanager-0

# Check services
kubectl get svc -n monitoring
```

## OAuth/SSO Configuration (Optional)

The monitoring stack supports OAuth/SSO integration with providers like Authentik, Keycloak, Google, GitHub, etc.

### Configure OAuth in custom-values.yaml

Uncomment and configure the `grafana.ini` section in `custom-values.yaml`:

```yaml
grafana:
  grafana.ini:
    auth:
      signout_redirect_url: https://auth.example.com
      oauth_auto_login: true  # Auto-login with OAuth
    auth.generic_oauth:
      name: Authentik  # Provider name shown on login page
      enabled: true
      client_id: "grafana-client-id"
      client_secret: "YOUR_CLIENT_SECRET"  # Move to secrets.yaml
      scopes: "openid profile email"
      auth_url: "https://auth.example.com/application/o/authorize/"
      token_url: "https://auth.example.com/application/o/token/"
      api_url: "https://auth.example.com/application/o/userinfo/"
    server:
      root_url: "https://grafana.example.com"
```

### Store OAuth Client Secret

Add OAuth secret to `secrets.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: grafana-oauth-credentials
  namespace: monitoring
type: Opaque
stringData:
  client-secret: "CHANGE_ME_OAUTH_CLIENT_SECRET"
```

Then reference it in `custom-values.yaml`:

```yaml
grafana:
  envFromSecret: grafana-oauth-credentials
  grafana.ini:
    auth.generic_oauth:
      client_secret: $__env{client-secret}
```

## Accessing Grafana

### Grafana Login

The default user is `admin`.

**Get the password from the secret you created:**

```bash
kubectl get secret grafana-admin-credentials -n monitoring \
  -o jsonpath="{.data.admin-password}" | base64 --decode; echo
```

**Access Grafana:**

- **Via Ingress:** https://grafana.yourdomain.com (if ingress configured)
- **Via Port Forward:**
  ```bash
  kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
  # Access at http://localhost:3000
  ```

## Dashboards

The stack includes default Prometheus dashboards. Additional Kubernetes dashboards from [dotdc/grafana-dashboards-kubernetes](https://github.com/dotdc/grafana-dashboards-kubernetes) are configured in `custom-values.yaml`.

### Included Dashboards

The `custom-values.yaml` configures these Kubernetes dashboards:

- **k8s-system-api-server**: API server metrics
- **k8s-system-coredns**: CoreDNS metrics
- **k8s-views-global**: Cluster-wide overview
- **k8s-views-namespaces**: Per-namespace metrics
- **k8s-views-nodes**: Node-level metrics
- **k8s-views-pods**: Pod-level metrics

These dashboards are automatically provisioned from the official repository.

### Accessing Dashboards

1. Log into Grafana
2. Navigate to **Dashboards** in the left menu
3. Look for the **Kubernetes** folder
4. Select a dashboard to view

### Add Custom Dashboards

To add more dashboards, update the `dashboards` section in `custom-values.yaml`:

```yaml
grafana:
  dashboards:
    grafana-dashboards-kubernetes:
      my-custom-dashboard:
        url: https://raw.githubusercontent.com/username/repo/dashboard.json
        token: ''
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -n monitoring

# Check pod logs
kubectl logs -n monitoring <pod-name>

# Check events
kubectl get events -n monitoring --sort-by='.lastTimestamp'

# Common issues:
# - Insufficient resources
# - Storage provisioner not available
# - CRD installation failed
```

### Grafana Not Accessible

```bash
# Check Grafana pod
kubectl get pods -n monitoring | grep grafana

# Check Grafana logs
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana

# Check ingress (if configured)
kubectl get ingress -n monitoring

# Port forward to test
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

### Prometheus Not Scraping Metrics

```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Visit http://localhost:9090/targets

# Check ServiceMonitor resources
kubectl get servicemonitor -n monitoring

# Check Prometheus operator logs
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-operator
```

### Dashboards Not Loading

```bash
# Check Grafana configuration
kubectl get configmap -n monitoring | grep grafana

# Check dashboard provisioning
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana | grep -i dashboard

# Verify internet access (dashboards loaded from GitHub)
kubectl run curl-test --rm -it --image=curlimages/curl --restart=Never -- \
  curl -I https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-views-global.json
```

## Migration from k3s-ansible

If you're migrating from the k3s-ansible `prometheus` role:

### Key Differences

| k3s-ansible | k8s-homelab |
|-------------|-------------|
| Ansible role with Jinja2 templates | Manual Helm install |
| Variables in `defaults/main.yml` | Helm values in `custom-values.yaml` |
| OAuth vars: `prometheus_grafana_openid_*` | OAuth in `grafana.ini` section |
| Chart version: v63.1.0 | Same version, update as needed |

### Migration Steps

1. **Export existing Grafana admin password:**
   ```bash
   kubectl get secret -n monitoring grafana-admin-credentials \
     -o jsonpath='{.data.admin-password}' | base64 -d
   ```

2. **Review OAuth configuration** (if enabled):
   - k3s-ansible used `prometheus_grafana_openid_enabled: true`
   - In k8s-homelab, uncomment OAuth section in `custom-values.yaml`
   - Transfer OAuth credentials to `secrets.yaml`

3. **Apply updated configuration:**
   ```bash
   helm upgrade prometheus prometheus-community/kube-prometheus-stack \
     --namespace monitoring \
     -f custom-values.yaml \
     --version 63.1.0
   ```

4. **No data loss**: Prometheus data persists in PVCs and is not affected by Helm upgrade.

### Ansible Variables Mapping

```yaml
# k3s-ansible (defaults/main.yml)
prometheus_enabled: true
prometheus_namespace: monitoring
prometheus_chart_version: 63.1.0
prometheus_grafana_admin_user: admin
prometheus_grafana_admin_password: "{{ vault_grafana_admin_password }}"
prometheus_grafana_ingress_enabled: true
prometheus_grafana_ingress_host: "grafana.example.com"
prometheus_grafana_openid_enabled: true
prometheus_grafana_openid_client_id: "grafana-client"
prometheus_grafana_openid_client_secret: "secret"

# k8s-homelab (custom-values.yaml)
grafana:
  admin:
    existingSecret: grafana-admin-credentials
  ingress:
    enabled: true
    hosts:
      - grafana.example.com
  grafana.ini:
    auth.generic_oauth:
      enabled: true
      client_id: "grafana-client"
      client_secret: "$__env{client-secret}"
```

### OAuth Migration

If you used OAuth in k3s-ansible:

1. **Identify OAuth variables** from your Ansible inventory
2. **Create secrets.yaml** with OAuth credentials
3. **Uncomment OAuth section** in `custom-values.yaml`
4. **Update URLs and client credentials**
5. **Apply secrets:** `kubectl apply -f secrets.yaml`
6. **Upgrade Helm release** with new values

## Additional Resources

- **Official Chart Documentation**: https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
- **Prometheus Documentation**: https://prometheus.io/docs/
- **Grafana Documentation**: https://grafana.com/docs/
- **Kubernetes Dashboards**: https://github.com/dotdc/grafana-dashboards-kubernetes
- **kube-prometheus-stack**: https://github.com/prometheus-operator/kube-prometheus

## Support

For issues or questions:
- Prometheus Community Helm Charts: https://github.com/prometheus-community/helm-charts/issues
- Prometheus Operator: https://github.com/prometheus-operator/prometheus-operator/issues
- Grafana Support: https://grafana.com/support/