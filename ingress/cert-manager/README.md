# cert-manager - X.509 Certificate Management for Kubernetes

## Overview

cert-manager is a Kubernetes add-on that automates the management and issuance of TLS certificates. It integrates with Let's Encrypt and other certificate authorities to automatically provision, renew, and manage certificates.

**Key features:**
- Automatic certificate issuance and renewal
- Integration with Let's Encrypt (DNS-01 and HTTP-01 challenges)
- Support for multiple DNS providers (Infomaniak, Route53, Cloudflare, DuckDNS, etc.)
- Certificate lifecycle management
- Integration with ingress-nginx for automatic TLS

## Prerequisites

- Kubernetes cluster with ingress-nginx installed
- kubectl configured to access your cluster
- Helm 3.x installed
- DNS provider account and API credentials

## Supported DNS Providers

This guide covers:
1. **Infomaniak** (recommended for Swiss hosting) - via webhook
2. **AWS Route53** (native support)
3. **Cloudflare** (native support)
4. **DuckDNS** (via webhook)
5. **Self-signed** (for local development/testing)

## Installation

### Step 1: Install cert-manager CRDs

**IMPORTANT:** cert-manager requires CRDs to be installed separately before the Helm chart.

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.1/cert-manager.crds.yaml
```

### Step 2: Add Helm Repository

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
```

### Step 3: Install cert-manager

```bash
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.17.1 \
  -f custom-values.yaml
```

### Step 4: Verify Installation

```bash
# Check pod status
kubectl get pods -n cert-manager

# Verify all three components are running
# - cert-manager
# - cert-manager-cainjector
# - cert-manager-webhook

# Wait for pods to be ready
kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=cert-manager \
  --timeout=120s
```

## Configuration

### DNS Resolution Settings

The `custom-values.yaml` configures cert-manager to use public DNS servers for DNS-01 challenge validation:

```yaml
extraArgs:
  - --dns01-recursive-nameservers=1.1.1.1:53,8.8.8.8:53
  - --dns01-recursive-nameservers-only
podDnsPolicy: None
podDnsConfig:
  nameservers:
    - 1.1.1.1  # Cloudflare DNS
    - 8.8.8.8  # Google DNS
```

**Why this matters:**
- Ensures cert-manager can validate DNS challenges even if cluster DNS is internal-only
- Prevents issues with split-horizon DNS configurations
- Required for reliable Let's Encrypt DNS-01 challenges

## DNS Provider Setup

### Option 1: Infomaniak (Recommended for Swiss Hosting)

Infomaniak is a Swiss hosting provider with excellent DNS services. cert-manager uses a webhook for Infomaniak integration.

#### 1.1. Install Infomaniak Webhook

```bash
# Install the Infomaniak webhook for cert-manager
helm repo add infomaniak https://infomaniak.github.io/cert-manager-webhook-infomaniak
helm repo update

helm install cert-manager-webhook-infomaniak infomaniak/cert-manager-webhook-infomaniak \
  --namespace cert-manager
```

**Reference:** [Infomaniak cert-manager webhook](https://github.com/Infomaniak/cert-manager-webhook-infomaniak)

#### 1.2. Get Infomaniak API Token

1. Log in to [Infomaniak Manager](https://manager.infomaniak.com/)
2. Navigate to: **API** > **API Dashboard**
3. Create a new API token with DNS management permissions
4. Copy the token (you won't be able to see it again!)

#### 1.3. Create Secret

```bash
# Copy the secrets template
cp secrets-template.yaml secrets.yaml

# Edit secrets.yaml and replace CHANGE_ME_INFOMANIAK_API_TOKEN
nano secrets.yaml

# Apply the secret
kubectl apply -f secrets.yaml
```

Or create directly:

```bash
kubectl create secret generic infomaniak-api-credentials \
  --namespace cert-manager \
  --from-literal=api-token='YOUR_INFOMANIAK_API_TOKEN'
```

#### 1.4. Create ClusterIssuer

```bash
# Edit cluster-issuer-infomaniak-prod.yaml and set your email
nano cluster-issuer-infomaniak-prod.yaml

# Apply the ClusterIssuer
kubectl apply -f cluster-issuer-infomaniak-prod.yaml

# For testing, use staging environment first
kubectl apply -f cluster-issuer-infomaniak-staging.yaml
```

#### 1.5. Verify ClusterIssuer

```bash
kubectl get clusterissuer letsencrypt-prod -o wide
# Should show Ready=True

kubectl describe clusterissuer letsencrypt-prod
# Check for "The ACME account was registered with the ACME server"
```

### Option 2: AWS Route53

#### 2.1. Create IAM User

Create an IAM user with the following policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:GetChange",
        "route53:ListHostedZones"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "route53:ChangeResourceRecordSets",
      "Resource": "arn:aws:route53:::hostedzone/*"
    }
  ]
}
```

#### 2.2. Create Secret

```bash
kubectl create secret generic route53-secret \
  --namespace cert-manager \
  --from-literal=secret-access-key='YOUR_AWS_SECRET_ACCESS_KEY'
```

#### 2.3. Create ClusterIssuer

Edit `cluster-issuer-route53-prod.yaml`:
- Set your email
- Set AWS region
- Set AWS access key ID

```bash
kubectl apply -f cluster-issuer-route53-prod.yaml
```

### Option 3: Cloudflare

#### 3.1. Create API Token

1. Go to [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Create token with:
   - **Permissions:** Zone - DNS - Edit
   - **Zone Resources:** Include - All zones (or specific zone)
3. Copy the token

#### 3.2. Create Secret

```bash
kubectl create secret generic cloudflare-api-token-secret \
  --namespace cert-manager \
  --from-literal=api-token='YOUR_CLOUDFLARE_API_TOKEN'
```

#### 3.3. Create ClusterIssuer

Create a file `cluster-issuer-cloudflare-prod.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: your-email@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - dns01:
        cloudflare:
          apiTokenSecretRef:
            name: cloudflare-api-token-secret
            key: api-token
```

```bash
kubectl apply -f cluster-issuer-cloudflare-prod.yaml
```

### Option 4: Self-Signed (Local Development)

For local testing without a real DNS provider:

```bash
# Create a self-signed CA certificate
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout tls.key -out tls.crt -subj "/CN=selfsigned-ca" \
  -addext "subjectAltName=DNS:example.com,DNS:*.example.com"

# Create secret from the certificate
kubectl create secret tls selfsigned-secret \
  --namespace cert-manager \
  --cert=tls.crt \
  --key=tls.key

# Apply the ClusterIssuer
kubectl apply -f cluster-issuer-selfsigned.yaml
```

**Note:** Self-signed certificates will trigger browser warnings. Use only for testing.

## Usage

### Automatic Certificate with Ingress

Once a ClusterIssuer is configured, certificates are automatically created via Ingress annotations:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-app
  namespace: default
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"  # References ClusterIssuer
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - app.yourdomain.com
    secretName: example-app-tls  # cert-manager will create this secret
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

**What happens:**
1. cert-manager detects the annotation
2. Creates a Certificate resource
3. Initiates DNS-01 challenge with your DNS provider
4. Obtains certificate from Let's Encrypt
5. Stores certificate in `example-app-tls` Secret
6. ingress-nginx uses the certificate for TLS termination

### Manual Certificate Resource

You can also create Certificate resources directly:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-com-cert
  namespace: default
spec:
  secretName: example-com-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - example.com
  - www.example.com
  - "*.example.com"  # Wildcard requires DNS-01 challenge
```

Apply and monitor:

```bash
kubectl apply -f certificate.yaml

# Watch certificate status
kubectl get certificate -n default
kubectl describe certificate example-com-cert -n default
```

## Troubleshooting

### 1. ClusterIssuer Not Ready

**Symptom:**
```bash
kubectl get clusterissuer letsencrypt-prod
# Shows Ready=False
```

**Debug:**
```bash
kubectl describe clusterissuer letsencrypt-prod
# Check Events and Conditions

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager
```

**Common causes:**
- Invalid DNS provider credentials
- Network connectivity issues
- ACME server rate limits

### 2. Certificate Stuck in Pending

**Symptom:**
```bash
kubectl get certificate
# Shows Ready=False for extended period
```

**Debug:**
```bash
# Describe the certificate
kubectl describe certificate <cert-name> -n <namespace>

# Check CertificateRequest
kubectl get certificaterequest -n <namespace>
kubectl describe certificaterequest <request-name> -n <namespace>

# Check Challenge (DNS-01)
kubectl get challenge -n <namespace>
kubectl describe challenge <challenge-name> -n <namespace>

# Check Order
kubectl get order -n <namespace>
kubectl describe order <order-name> -n <namespace>
```

**Common causes:**
- DNS propagation not complete (wait 2-5 minutes)
- DNS provider API errors (check credentials)
- Firewall blocking cert-manager egress to ACME server

### 3. DNS-01 Challenge Failing

**Symptom:**
Challenge shows "Waiting for DNS-01 challenge propagation"

**Debug:**
```bash
# Check if DNS record was created
dig _acme-challenge.yourdomain.com TXT

# Check cert-manager logs for DNS provider errors
kubectl logs -n cert-manager deployment/cert-manager | grep -i dns

# For Infomaniak: verify webhook is running
kubectl get pods -n cert-manager | grep infomaniak
```

**Solutions:**
- Verify DNS provider API token has correct permissions
- Check DNS provider's API rate limits
- Ensure cert-manager can reach DNS provider API (no firewall blocking)

### 4. Rate Limit Errors from Let's Encrypt

**Symptom:**
Error message: "too many certificates already issued"

**Cause:**
Let's Encrypt has rate limits:
- 50 certificates per registered domain per week
- 5 duplicate certificates per week

**Solution:**
- Use staging environment for testing: `letsencrypt-staging`
- Wait for rate limit window to reset (7 days)
- Consider using wildcard certificates to reduce certificate count

### 5. Webhook Not Found (Infomaniak)

**Symptom:**
```
Error: no solvers configured for DNS01 challenge
```

**Debug:**
```bash
# Verify webhook is installed
kubectl get pods -n cert-manager | grep infomaniak

# Check webhook logs
kubectl logs -n cert-manager deployment/cert-manager-webhook-infomaniak
```

**Solution:**
Reinstall the Infomaniak webhook:
```bash
helm upgrade --install cert-manager-webhook-infomaniak \
  infomaniak/cert-manager-webhook-infomaniak \
  --namespace cert-manager
```

### 6. Certificate Renewal Issues

**Symptom:**
Certificate expiring or not auto-renewing

**Debug:**
```bash
# Check certificate expiry
kubectl get certificate -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[0].status,EXPIRY:.status.notAfter'

# Check renewal history
kubectl describe certificate <cert-name> -n <namespace>
```

**Solution:**
- cert-manager renews certificates 30 days before expiry
- Manual renewal: `kubectl delete secret <tls-secret-name>` (cert-manager recreates it)
- Check cert-manager logs for errors

## Upgrading

### Check for Breaking Changes

Review the [cert-manager changelog](https://cert-manager.io/docs/releases/) before upgrading.

### Upgrade CRDs First

**IMPORTANT:** Always upgrade CRDs before the Helm chart.

```bash
# Backup existing certificates
kubectl get certificate -A -o yaml > certificates-backup.yaml

# Upgrade CRDs
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/<NEW_VERSION>/cert-manager.crds.yaml

# Upgrade Helm release
helm repo update

helm upgrade cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version <NEW_VERSION> \
  -f custom-values.yaml

# Verify
kubectl rollout status deployment/cert-manager -n cert-manager
kubectl rollout status deployment/cert-manager-cainjector -n cert-manager
kubectl rollout status deployment/cert-manager-webhook -n cert-manager
```

## Best Practices

### 1. Use Staging for Testing

Always test with `letsencrypt-staging` before switching to production:

```yaml
cert-manager.io/cluster-issuer: "letsencrypt-staging"
```

Staging certificates will show browser warnings but won't count against rate limits.

### 2. Use Wildcard Certificates

Reduce certificate count with wildcards:

```yaml
dnsNames:
- "*.yourdomain.com"
- "yourdomain.com"
```

**Note:** Wildcard certificates require DNS-01 challenge (HTTP-01 doesn't support wildcards).

### 3. Monitor Certificate Expiry

Set up monitoring for certificate expiration:

```bash
# Get all certificates and expiry dates
kubectl get certificate -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,EXPIRY:.status.notAfter'
```

Consider integrating with Prometheus/Grafana for alerts.

### 4. Backup Certificates

```bash
# Backup all TLS secrets
kubectl get secret -A -o json | \
  jq -r '.items[] | select(.type=="kubernetes.io/tls")' > tls-secrets-backup.json
```

### 5. Secure DNS Provider Credentials

- Use Kubernetes secrets (never commit to git)
- Rotate API tokens periodically
- Use RBAC to restrict access to cert-manager namespace

## Migration from k3s-ansible

- **Source:** `roles/kubernetes/cert_manager/`
- **Chart version:** v1.17.1 (unchanged)
- **Variables converted:**
  - `cert_manager_enabled` → Removed (deployment is manual)
  - `cert_manager_namespace` → Documented as `cert-manager`
  - `cert_manager_chart_version` → Documented in README
  - `cert_manager_dns_provider` → Multiple ClusterIssuer manifests provided
  - `cert_manager_route53_*` → secrets-template.yaml
  - DNS provider credentials → secrets-template.yaml

### New Features in Migration

1. **Infomaniak Support:** Added dedicated ClusterIssuer and webhook instructions (not in k3s-ansible)
2. **Multiple DNS Providers:** All providers documented with examples
3. **Comprehensive Troubleshooting:** Detailed debugging steps for common issues
4. **Best Practices:** Production recommendations for certificate management

## Additional Resources

- [Official Documentation](https://cert-manager.io/docs/)
- [Helm Chart Repository](https://github.com/cert-manager/cert-manager/tree/master/deploy/charts/cert-manager)
- [Infomaniak Webhook](https://github.com/Infomaniak/cert-manager-webhook-infomaniak)
- [DNS Provider Configuration](https://cert-manager.io/docs/configuration/acme/dns01/)
- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)
- [Troubleshooting Guide](https://cert-manager.io/docs/troubleshooting/)

## Sources

- [Infomaniak cert-manager webhook](https://github.com/Infomaniak/cert-manager-webhook-infomaniak)
- [cert-manager DNS01 documentation](https://cert-manager.io/docs/configuration/acme/dns01/)
