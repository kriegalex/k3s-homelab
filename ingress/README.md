# Guide to Migrating from Nginx Proxy Manager to Nginx Ingress on Kubernetes

Migrating from Nginx Proxy Manager to using a proper Nginx Ingress on a Kubernetes cluster involves several steps and components. This guide will cover the principles and steps necessary to achieve this migration. We assume you have a modern version of Kubernetes running and are familiar with the basics of Kubernetes operations.

## Principles

1. Separation of Concerns: In a Kubernetes environment, it is crucial to separate concerns by dividing your services into smaller, manageable pieces.
2. Scalability: Kubernetes and Helm facilitate horizontal scaling, ensuring your services can handle increased loads.
3. Security: Properly managed Ingress controllers and certificates ensure secure communication.
4. Automation: Using tools like Helm and Kubernetes manifests to automate deployments ensures consistency and reliability.

## Components of the Cluster

1. Kubernetes Cluster: Ensure your Kubernetes cluster is [up and running](../INSTALL.md).
2. Helm: Helm will be used to manage Kubernetes applications.
3. Cert-Manager: This will handle obtaining and renewing SSL certificates.
4. Nginx Ingress Controller: This will replace the Nginx Proxy Manager.
5. AWS Route53: For DNS management and certificate provisioning.

## Step-by-Step Migration

### Install Helm

If you haven't installed Helm, install it using the following commands:

```
wget https://get.helm.sh/helm-v3.15.0-linux-amd64.tar.gz
```

```
tar -zxvf helm-v3.15.0-linux-amd64.tar.gz
sudo mv linux-amd64/helm /usr/local/bin/helm
```

```
helm help
```

### Install Nginx Ingress Controller

Use Helm to install the Nginx Ingress Controller:

```
helm upgrade --set controller.service.externalTrafficPolicy=Local \
  --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace
```

This command installs the Nginx Ingress Controller. To learn about externalTrafficPolicy, please check [this documentation](https://metallb.universe.tf/usage/#traffic-policies) or [this one](https://kubernetes.github.io/ingress-nginx/user-guide/retaining-client-ipaddress/).

(optional) If you plan to use server-snippet annotations in Ingress resources, you must add another setting:

```
helm upgrade --set controller.service.externalTrafficPolicy=Local \
  --set controller.allowSnippetAnnotations=true \
  --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace
```

This annotation is used for example [by Nextcloud](https://github.com/nextcloud/helm/blob/main/charts/nextcloud/values.yaml).

To see all the available values that you can set:

```
helm show values ingress-nginx --repo https://kubernetes.github.io/ingress-nginx
```

### Install Cert-Manager

Cert-Manager will automate the management of your SSL certificates:

```
helm repo add jetstack https://charts.jetstack.io --force-update

helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.15.1 \
  --set crds.enabled=true
```

Create a ClusterIssuer for AWS Route53:

```
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - dns01:
        route53:
          region: your-region
          hostedZoneID: your-hosted-zone-id
          accessKeyID: your-access-key-id
          secretAccessKeySecretRef:
            name: route53-secret
            key: secret-access-key
```

Create a secret for Route53 access:

```
kubectl -n cert-manager create secret generic route53-secret --from-literal=secret-access-key=your-secret-access-key
```

! Do not skip the namespace if you installed cert-manager in a namespace !

Apply this configuration:

```
kubectl apply -f cluster-issuer.yaml
```

### Testing

Before going any further, let's test that everything is working as expected:

```
kubectl create deployment demo --image=httpd --port=80
kubectl expose deployment demo
```

If you followed the main [INSTALL.md](../INSTALL.md) from this repository, you should have MetalLB acting as a load balancer, so no need to do a port forwarding.

```
kubectl create ingress demo --class=nginx \
  --rule="www.demo.io/*=demo:80"
```

You should then be able to see the "It works!" page when you connect to http://www.demo.io/.

(optional) If you don't have a load balancer:

```
kubectl port-forward --namespace=ingress-nginx service/ingress-nginx-controller 8080:80
```

(optional) Don't forget to modify or setup any port forwarding on your homelab router, so that the port 80 is forwarded to the IP of the ingress-nginx service. You can check the IP with the command below. The field <EXTERNAL-IP> should be filled for `ingress-nginx-controller`. Otherwise, your MetalLB may not be configured correctly.

```
kubectl -n ingress-nginx get svc ingress-nginx-controller
```

#### HTTPS

We can also test HTTPS using [the Ingress demo-io-https](./test-https.yaml). Please modify it so that it matches your domain (not demo.io).

```
kubectl delete ingress demo
kubectl apply -f test-https.yaml
```

After some time, the certificate should be ready to use. To check that the certificate was generated correctly:

```
kubectl get certificates
```

A certificate `demo-io-tls` should appear in the list with READY state True. You can troubleshoot any issues by looking at the CertificateRequests, Orders, ClusterIssuer or look at the logs of the cert-manager pod:

```
kubectl get certificaterequests
kubectl get orders
kubectl describe clusterissuer letsencrypt-prod
kubectl -n cert-manager logs cert-manager-XXXX-YY
```

You should then be able to see the "It works!" page when you connect to https://www.demo.io/.

(optional) Modify your networking config for HTTPS.

#### Clean testing resources

```
kubectl delete -f test-https.yaml
kubectl delete deployment demo
kubectl delete svc demo
```

### Migrate Nginx Proxy Manager Configurations

Convert your Nginx Proxy Manager configurations to Kubernetes Ingress resources. Here is an example:

Nginx Proxy Manager Config:

```
server {
    listen PORT;
    server_name service.example.com;
    location / {
        proxy_pass http://your-service-ip:PORT;
    }
}
```

Kubernetes Ingress Resource:

```
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-service
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  rules:
  - host: service.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: your-service
            port:
              number: PORT
  tls:
  - hosts:
    - service.example.com
    secretName: service-tls
```

Please pay attention to the annotation and the secretName !

Apply the Ingress resource:

```
kubectl apply -f ingress-service.yaml
```

(optional) If your service is running outside of the kubernetes cluster, you don't have any service name to point to. In that scenario, you need to create an external service and an endpoint for kubernetes to know where to point that domain to:

```
apiVersion: v1
kind: Service
metadata:
  name: your-service
  namespace: default
spec:
  ports:
  - protocol: TCP
    port: PORT
    targetPort: PORT

---

apiVersion: v1
kind: Endpoints
metadata:
  name: your-service
  namespace: default
subsets:
  - addresses:
      - ip: your-service-ip
    ports:
      - port: PORT
```

You can find some concrete examples in the subfolders (plex, ...).

## Ingress Rules Organization

Application-specific ingress rules are organized under `/ingress/rules/` by category:

- `/ingress/rules/media-automation/` - Media automation stack ingress rules (overseerr)
- `/ingress/rules/productivity/` - Productivity app ingress rules (gitea, nextcloud)
- `/ingress/rules/standalone/` - Standalone service ingress rules (plex)

This organization mirrors the application directory structure and keeps ingress infrastructure (cert-manager, ingress-nginx) separate from app-specific routing rules.

### Conclusion

By following these steps, you have migrated from Nginx Proxy Manager to using a proper Nginx Ingress on Kubernetes. This setup enhances scalability, security, and maintainability of your applications.

## Summary

1. Install Helm: Manage Kubernetes applications.
2. Install Nginx Ingress Controller: Route traffic within your cluster.
3. Install Cert-Manager: Automate SSL certificate management.
4. Create ClusterIssuer and Secrets: For AWS Route53.
5. Verify and Test: Ensure everything is working correctly.
6. Migrate Configurations: Convert Nginx Proxy Manager configurations to Kubernetes Ingress resources.
