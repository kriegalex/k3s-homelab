# k8s-homelab Installation Guide

Complete step-by-step guide to deploy a production-ready Kubernetes homelab stack with infrastructure components and applications.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Infrastructure Components](#infrastructure-components)
  - [1. Ingress Layer](#1-ingress-layer)
  - [2. Storage Layer](#2-storage-layer)
  - [3. Database Layer](#3-database-layer)
  - [4. Backup Layer](#4-backup-layer)
  - [5. Monitoring Layer](#5-monitoring-layer)
- [Applications](#applications)
  - [Productivity & Document Management](#productivity--document-management)
  - [Media Management](#media-management)
  - [Media Organization (*arr Stack)](#media-organization-arr-stack)
  - [Downloads & Utilities](#downloads--utilities)
  - [Development & Infrastructure](#development--infrastructure)
  - [Game Servers](#game-servers)
  - [Network Services](#network-services)
- [Common Patterns](#common-patterns)
- [Troubleshooting](#troubleshooting)

## Overview

**k8s-homelab** is a comprehensive Kubernetes application platform that provides infrastructure components and ready-to-deploy applications for your homelab.

**What this repository provides:**
- Infrastructure deployment (ingress, storage, database, backup, monitoring)
- Application Helm charts and configurations
- Complete documentation and troubleshooting guides

**What this repository does NOT provide:**
- Kubernetes cluster provisioning → Use [k3s-ansible](https://github.com/kriegalex/k3s-ansible) for cluster setup

**Deployment Architecture:**
```
┌─────────────────────────────────────────────────────┐
│  k3s-ansible: Cluster Provisioning                  │
│  - k3s cluster setup                                │
│  - kube-vip / MetalLB (LoadBalancer)                │
│  - CNI (Flannel/Calico/Cilium)                      │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│  k8s-homelab: Infrastructure + Applications         │
│  - Ingress (Traefik, cert-manager)                  │
│  - Storage (Longhorn, NFS)                          │
│  - Database (CloudNativePG)                         │
│  - Backup (k8up)                                    │
│  - Applications (Nextcloud, Plex, Gitea, etc.)      │
└─────────────────────────────────────────────────────┘
```

## Prerequisites

### 1. Running Kubernetes Cluster

You **must** have a Kubernetes cluster running before using k8s-homelab.

**Recommended:** Use [k3s-ansible](https://github.com/kriegalex/k3s-ansible) to provision your cluster:
- Automated k3s deployment with HA
- Pre-configured MetalLB for LoadBalancer services
- CNI options: Flannel, Calico, Cilium
- See [k3s-ansible INSTALL.md](https://github.com/kriegalex/k3s-ansible/blob/main/INSTALL.md)

### 2. Required Tools

Ensure these tools are installed on your local machine:

```bash
# Verify kubectl
kubectl cluster-info
kubectl version --client

# Verify Helm
helm version

# Verify cluster access
kubectl get nodes
```

**Installation guides:**
- kubectl: https://kubernetes.io/docs/tasks/tools/
- helm: https://helm.sh/docs/intro/install/

### 3. Cluster Requirements

- Kubernetes v1.25+ (v1.28+ recommended)
- At least 3 nodes (1 control plane + 2 workers) for HA
- LoadBalancer provider (MetalLB, kube-vip)
- Minimum resources per node:
  - 4 CPU cores
  - 8GB RAM
  - 50GB disk space

### 4. DNS and Networking

- Functional DNS resolution (public DNS or local DNS server)
- Internet access for downloading Helm charts and container images
- Firewall rules allowing:
  - Port 80/443 for ingress traffic
  - Inter-node communication for CNI
  - LoadBalancer IP range accessible from your network

---

## Infrastructure Components

Infrastructure components provide the foundation for all applications. Deploy these **in order** as they have dependencies on each other.

### 1. Ingress Layer

The ingress layer handles external HTTP/HTTPS traffic routing to your services.

#### 1.1. Traefik - Ingress Controller

**What it does:** Routes external traffic to Kubernetes services based on hostnames and paths. Replaced ingress-nginx in April 2026; see `~/workspace/traefik-migration/MIGRATION_GUIDE.md` for the historical migration playbook.

**Prerequisites:**
- MetalLB or another LoadBalancer provider (from k3s-ansible)

**Quick Start:**

```bash
# Add Helm repository
helm repo add traefik https://traefik.github.io/charts
helm repo update

# Install Traefik
helm upgrade --install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace \
  --version 39.0.8 \
  -f ingress/traefik/values.yaml

# Apply the dashboard IngressRoute and shared middlewares
kubectl apply -f ingress/traefik/ingressroute-dashboard.yaml
kubectl apply -f ingress/traefik/middlewares/

# Verify installation
kubectl get pods -n traefik
kubectl get svc -n traefik traefik
kubectl get ingressclass traefik
```

**Verify:**
```bash
# Should show EXTERNAL-IP from MetalLB (10.0.0.20 in this homelab)
kubectl get svc -n traefik traefik
```

**Details:** See [Traefik README](ingress/traefik/README.md) for the chart pinning, middleware inventory, and per-Ingress conventions.

---

#### 1.2. cert-manager - TLS Certificate Management

**What it does:** Automates SSL/TLS certificate issuance and renewal from Let's Encrypt using DNS challenges.

**Prerequisites:**
- Traefik installed (or any Ingress controller — cert-manager is controller-agnostic)
- DNS provider account (Infomaniak, Route53, Cloudflare, or DuckDNS)
- DNS provider API credentials

**Quick Start:**

```bash
# Step 1: Install CRDs (REQUIRED)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.1/cert-manager.crds.yaml

# Step 2: Add Helm repository
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Step 3: Install cert-manager
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.17.1 \
  -f ingress/cert-manager/custom-values.yaml

# Step 4: Create DNS provider secret
cp ingress/cert-manager/secrets-template.yaml ingress/cert-manager/secrets.yaml
# Edit secrets.yaml with your DNS provider API token
nano ingress/cert-manager/secrets.yaml

kubectl apply -f ingress/cert-manager/secrets.yaml

# Step 5: Install DNS provider webhook (example for Infomaniak)
helm repo add infomaniak https://infomaniak.github.io/cert-manager-webhook-infomaniak
helm repo update

helm install cert-manager-webhook-infomaniak infomaniak/cert-manager-webhook-infomaniak \
  --namespace cert-manager

# Step 6: Create ClusterIssuer
# Edit cluster-issuer to set your email
nano ingress/cert-manager/cluster-issuer-infomaniak-prod.yaml

kubectl apply -f ingress/cert-manager/cluster-issuer-infomaniak-prod.yaml
```

**Verify:**
```bash
kubectl get pods -n cert-manager
kubectl get clusterissuer letsencrypt-prod
# Should show Ready=True
```

**Details:** See [cert-manager README](ingress/cert-manager/README.md) for:
- DNS provider setup (Infomaniak, Route53, Cloudflare, DuckDNS)
- ClusterIssuer configuration
- Troubleshooting DNS-01 challenges
- Rate limits and best practices

---

### 2. Storage Layer

Storage provides persistent data for applications. Choose **one** storage backend.

#### Option A: Longhorn - Distributed Block Storage (Recommended for HA)

**What it does:** Provides replicated block storage across cluster nodes for high availability.

**Prerequisites:**
- **open-iscsi installed on ALL nodes** (critical requirement)
- At least 3 worker nodes (for replication)
- Sufficient disk space on each node

**Node Preparation (REQUIRED):**

You need to run these commands **with sudo privileges** on EACH node:

```bash
# Ubuntu/Debian nodes
sudo apt-get update
sudo apt-get install -y open-iscsi
sudo systemctl enable --now iscsid

# RHEL/Rocky/Fedora nodes
sudo yum install -y iscsi-initiator-utils
sudo systemctl enable --now iscsid

# Verify installation
sudo systemctl status iscsid
```

**⚠️ Important:** These sudo commands must be run manually on each node or via configuration management (Ansible). They cannot be executed via kubectl.

**Quick Start:**

```bash
# Add Helm repository
helm repo add longhorn https://charts.longhorn.io
helm repo update

# Install Longhorn
helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --version 1.8.1-rc2 \
  -f storage/longhorn/custom-values.yaml

# Wait for installation (may take 2-3 minutes)
kubectl wait --namespace longhorn-system \
  --for=condition=ready pod \
  --selector=app=longhorn-manager \
  --timeout=300s
```

**Verify:**
```bash
kubectl get pods -n longhorn-system
kubectl get storageclass longhorn
# Should show longhorn as (default)
```

**Optional - Enable S3 Backups:**

```bash
# Create S3 credentials secret
cp storage/longhorn/secrets-template.yaml storage/longhorn/secrets.yaml
# Edit with S3 credentials
nano storage/longhorn/secrets.yaml
kubectl apply -f storage/longhorn/secrets.yaml

# Update custom-values.yaml with backupTarget
# Then upgrade Helm release
helm upgrade longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --version 1.8.1-rc2 \
  -f storage/longhorn/custom-values.yaml
```

**Details:** See [Longhorn README](storage/longhorn/README.md) for:
- S3 backup configuration
- UI access (port-forward or ingress)
- Volume management
- Troubleshooting volume attachment issues

---

#### Option B: NFS Provisioner - Shared Network Storage (Retired 2026-07)

> This provisioner was uninstalled 2026-07 (broken 152 days, zero consumers) and the `nfs-client`
> StorageClass deleted. Kept below for historical reference only — do not follow these steps without
> re-evaluating the NFS topology first. Longhorn (Option A) is the only supported dynamic provisioner now.

**What it does:** Automatically provisions PersistentVolumes from an existing NFS server.

**Prerequisites:**
- NFS server with exported share
- **nfs-common installed on ALL nodes**

**Node Preparation:**

```bash
# Ubuntu/Debian nodes
sudo apt-get update
sudo apt-get install -y nfs-common

# RHEL/Rocky/Fedora nodes
sudo yum install -y nfs-utils
```

**Quick Start:**

```bash
# Add Helm repository
helm repo add nfs-subdir-external-provisioner \
  https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm repo update

# Install NFS provisioner
# Edit custom-values.yaml with your NFS server IP and path
helm upgrade --install nfs-subdir-external-provisioner \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace kube-system \
  -f storage/nfs-shares/nfs-client/custom-values.yaml
```

**Verify:**
```bash
kubectl get pods -n kube-system | grep nfs
kubectl get storageclass nfs-client
```

**Details:** See [NFS Provisioner README](storage/nfs-shares/nfs-client/README.md) for NFS server setup and troubleshooting.

---

### 3. Database Layer

#### CloudNativePG - PostgreSQL Operator

**What it does:** Manages PostgreSQL databases natively in Kubernetes with HA, automated failover, and backups.

**Prerequisites:**
- Storage provisioner (Longhorn or NFS)

**Quick Start:**

```bash
# Add Helm repository
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update

# Install the operator
helm upgrade --install cnpg cnpg/cloudnative-pg \
  --namespace cnpg-system \
  --create-namespace \
  -f database/cloudnative-pg/custom-values.yaml \
  --version 0.23.0
```

**Verify:**
```bash
kubectl get pods -n cnpg-system
kubectl get crd | grep cnpg
```

**Create a PostgreSQL Cluster:**

Applications will create their own database clusters. For manual cluster creation:

```bash
# Example: Create a 3-instance HA cluster
kubectl apply -f database/cloudnative-pg/example-cluster.yaml

# Verify cluster
kubectl get cluster -n default
kubectl get pods -n default | grep postgres
```

**Details:** See [CloudNativePG README](database/cloudnative-pg/README.md) for:
- Cluster creation
- Connection details
- Backup/restore configuration
- High availability setup

---

### 4. Backup Layer

#### k8up - Backup Operator

**What it does:** Automates backup and restore of PersistentVolumeClaims and databases to S3-compatible storage.

**Prerequisites:**
- S3-compatible storage (AWS S3, MinIO, Wasabi, Backblaze B2, etc.)
- S3 credentials (access key and secret key)
- Restic encryption password

**Quick Start:**

```bash
# Step 1: Install CRDs
kubectl apply -f https://github.com/k8up-io/k8up/releases/download/k8up-4.8.3/k8up-crd.yaml

# Step 2: Add Helm repository
helm repo add k8up-io https://k8up-io.github.io/k8up
helm repo update

# Step 3: Create backup secrets
cp backup/k8up/secrets-template.yaml backup/k8up/secrets.yaml
# Edit with S3 credentials and Restic password
nano backup/k8up/secrets.yaml
kubectl apply -f backup/k8up/secrets.yaml

# Step 4: Install k8up operator
helm upgrade --install k8up k8up-io/k8up \
  --namespace k8up-system \
  --create-namespace \
  -f backup/k8up/custom-values.yaml \
  --version 4.8.3
```

**Verify:**
```bash
kubectl get pods -n k8up-system
kubectl get crd | grep k8up.io
```

**Details:** See [k8up README](backup/k8up/README.md) for:
- Scheduled backup configuration
- Database backup annotations
- Restore procedures
- Retention policies

---

### 5. Monitoring Layer

#### Prometheus + Grafana Stack

**What it does:** Provides metrics collection, monitoring dashboards, and alerting for your cluster.

**Prerequisites:**
- Storage provisioner (for Grafana and Prometheus data)

**Quick Start:**

```bash
# Create secrets for Grafana admin password
cp monitoring/secrets-template.yaml monitoring/secrets.yaml
# Edit with secure password
nano monitoring/secrets.yaml
kubectl apply -f monitoring/secrets.yaml

# Add Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus stack
helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f monitoring/custom-values.yaml \
  --version 67.7.0
```

**Verify:**
```bash
kubectl get pods -n monitoring
```

**Access Grafana:**

```bash
# Port-forward to access locally
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Access at: http://localhost:3000
# Username: admin
# Password: (from secrets.yaml)
```

**Details:** See [Monitoring README](monitoring/README.md) for:
- Ingress configuration
- OAuth setup
- Dashboard management
- Alert configuration

---

## Applications

Applications are organized by category. Each application can be deployed independently.

### Productivity & Document Management

#### Nextcloud - File Sync & Share Platform

**What it does:** Self-hosted file synchronization and sharing, similar to Dropbox/Google Drive.

**Prerequisites:**
- CloudNativePG operator installed
- Storage provisioner (Longhorn or NFS)
- Ingress with TLS configured

**Quick Start:**

```bash
# Step 1: Create namespace
kubectl create namespace nextcloud

# Step 2: Create PostgreSQL cluster
kubectl apply -f nextcloud/postgres-cluster.yaml

# Step 3: Create secrets
cp nextcloud/secrets-template.yaml nextcloud/secrets.yaml
# Edit with admin password, database credentials, Redis password
nano nextcloud/secrets.yaml
kubectl apply -f nextcloud/secrets.yaml

# Step 4: Install Nextcloud
helm repo add nextcloud https://nextcloud.github.io/helm
helm repo update

helm upgrade --install nextcloud nextcloud/nextcloud \
  --namespace nextcloud \
  -f nextcloud/custom-values.yaml
```

**Verify:**
```bash
kubectl get pods -n nextcloud
kubectl get ingress -n nextcloud
```

**Details:** See [Nextcloud README](nextcloud/README.md) for Docker migration, Collabora integration, and backup procedures.

---

#### Paperless-NGX - Document Management System

**What it does:** Scans, indexes, and archives your documents with OCR and full-text search.

**Prerequisites:**
- CloudNativePG operator
- Storage provisioner
- Ingress with TLS

**Quick Start:**

```bash
# Create namespace
kubectl create namespace paperless

# Create PostgreSQL cluster
kubectl apply -f paperless-ngx/postgres-cluster.yaml

# Create secrets
cp paperless-ngx/secrets-template.yaml paperless-ngx/secrets.yaml
nano paperless-ngx/secrets.yaml
kubectl apply -f paperless-ngx/secrets.yaml

# Install Paperless-NGX
helm repo add gabe565 https://charts.gabe565.com
helm repo update

helm upgrade --install paperless gabe565/paperless-ngx \
  --namespace paperless \
  -f paperless-ngx/custom-values.yaml
```

**Verify:**
```bash
kubectl get pods -n paperless
kubectl get ingress -n paperless
```

**Details:** See [Paperless-NGX README](paperless-ngx/README.md).

---

#### Actual Budget - Personal Finance Management

**What it does:** Privacy-focused budgeting app with bank sync capabilities.

**Prerequisites:**
- Storage provisioner
- Ingress with TLS

**Quick Start:**

```bash
# Create namespace
kubectl create namespace actual-budget

# Install Actual Budget
helm repo add k8s-charts https://kriegalex.github.io/k8s-charts/
helm repo update

helm upgrade --install actual-budget k8s-charts/actual-budget \
  --namespace actual-budget \
  -f actual-budget/custom-values.yaml
```

**Verify:**
```bash
kubectl get pods -n actual-budget
kubectl get ingress -n actual-budget
```

**Details:** See [Actual Budget README](actual-budget/README.md).

---

#### N8N - Workflow Automation

**What it does:** Low-code workflow automation platform (similar to Zapier/Make).

**Prerequisites:**
- CloudNativePG operator
- Storage provisioner
- Ingress with TLS

**Quick Start:**

```bash
# Create namespace
kubectl create namespace n8n

# Create PostgreSQL cluster
kubectl apply -f n8n/postgres-cluster.yaml

# Create secrets
cp n8n/secrets-template.yaml n8n/secrets.yaml
nano n8n/secrets.yaml
kubectl apply -f n8n/secrets.yaml

# Install N8N
helm upgrade --install n8n oci://8gears.container-registry.com/library/n8n \
  --namespace n8n \
  -f n8n/custom-values.yaml
```

**Verify:**
```bash
kubectl get pods -n n8n
kubectl get ingress -n n8n
```

**Details:** See [N8N README](n8n/README.md).

---

### Media Management

#### Plex - Media Server with GPU Transcoding

**What it does:** Organizes and streams your media library with hardware transcoding support (Intel ARC GPU).

**Prerequisites:**
- Storage provisioner
- NFS shares for media (movies, TV shows, music)
- Intel GPU on node (for hardware transcoding)
- Ingress with TLS

**Quick Start:**

```bash
# Create namespace
kubectl create namespace plex

# Create PersistentVolumes for media shares
kubectl apply -f plex/pv-movies.yaml
kubectl apply -f plex/pv-tvshows.yaml

# Create secrets
cp plex/secrets-template.yaml plex/secrets.yaml
# Edit with Plex Claim Token (from https://plex.tv/claim)
nano plex/secrets.yaml
kubectl apply -f plex/secrets.yaml

# Install Plex
helm repo add plex https://raw.githubusercontent.com/plexinc/pms-docker/gh-pages
helm repo update

helm upgrade --install plex-media-server plex/plex-media-server \
  --namespace plex \
  -f plex/custom-values.yaml
```

**Verify:**
```bash
kubectl get pods -n plex
kubectl get ingress -n plex
```

**Details:** See [Plex README](plex/README.md) for GPU setup, transcoding configuration, and optimization.

---

#### Jellyfin - Open-Source Media Server

**What it does:** Free and open-source alternative to Plex.

**Prerequisites:**
- Storage provisioner
- NFS shares for media
- Ingress with TLS

**Quick Start:**

```bash
# Create namespace
kubectl create namespace jellyfin

# Create PersistentVolumes for media
kubectl apply -f jellyfin/pv-media.yaml

# Install Jellyfin
helm repo add k8s-charts https://kriegalex.github.io/k8s-charts/
helm repo update

helm upgrade --install jellyfin k8s-charts/jellyfin \
  --namespace jellyfin \
  -f jellyfin/custom-values.yaml
```

**Verify:**
```bash
kubectl get pods -n jellyfin
kubectl get ingress -n jellyfin
```

**Details:** See [Jellyfin README](jellyfin/README.md).

---

#### Immich - Photo Management & Backup

**What it does:** Self-hosted photo and video backup solution with mobile apps (similar to Google Photos).

**Prerequisites:**
- CloudNativePG operator
- Storage provisioner (high capacity recommended)
- Ingress with TLS

**Quick Start:**

```bash
# Create namespace
kubectl create namespace immich

# Create PostgreSQL cluster with pgvecto.rs extension
kubectl apply -f immich/postgres-cluster.yaml

# Create secrets
cp immich/secrets-template.yaml immich/secrets.yaml
nano immich/secrets.yaml
kubectl apply -f immich/secrets.yaml

# Install Immich
helm repo add immich https://immich-app.github.io/immich-charts
helm repo update

helm upgrade --install immich immich/immich \
  --namespace immich \
  -f immich/custom-values.yaml
```

**Verify:**
```bash
kubectl get pods -n immich
kubectl get ingress -n immich
```

**Details:** See [Immich README](immich/README.md) for Docker migration and mobile app setup.

---

### Media Organization (*arr Stack)

The *arr stack automates media organization and acquisition.

#### Prowlarr - Indexer Manager

**What it does:** Manages indexers (torrent trackers) for Radarr, Sonarr, and Lidarr.

**Prerequisites:**
- Storage provisioner
- Ingress with TLS

**Quick Start:**

```bash
# Create media namespace (shared by all *arr apps)
kubectl create namespace media

helm repo add alekc https://charts.alekc.dev
helm repo update

helm upgrade --install prowlarr alekc/prowlarr \
  --namespace media \
  -f prowlarr/custom-values.yaml
```

**Verify:**
```bash
kubectl get pods -n media | grep prowlarr
kubectl get ingress -n media | grep prowlarr
```

**Details:** See [Prowlarr README](prowlarr/README.md).

---

#### Radarr - Movie Collection Manager

**What it does:** Automates movie downloads and organization.

**Prerequisites:**
- NFS share for movies
- qBittorrent installed
- Prowlarr configured
- Ingress with TLS

**Quick Start:**

```bash
# Use media namespace (created for Prowlarr)
# Create PV for movies
kubectl apply -f radarr/pv-movies.yaml

helm repo add alekc https://charts.alekc.dev
helm repo update

helm upgrade --install radarr alekc/radarr \
  --namespace media \
  -f radarr/custom-values.yaml
```

**Verify:**
```bash
kubectl get pods -n media | grep radarr
kubectl get ingress -n media | grep radarr
```

**Details:** See [Radarr README](radarr/README.md).

---

#### Sonarr - TV Show Collection Manager

**What it does:** Automates TV show downloads and organization.

**Prerequisites:**
- NFS share for TV shows
- qBittorrent installed
- Prowlarr configured
- Ingress with TLS

**Quick Start:**

```bash
# Use media namespace (created for Prowlarr)
# Create PV for TV shows
kubectl apply -f sonarr/pv-tvshows.yaml

# Install Sonarr (main instance for TV shows)
helm repo add alekc https://charts.alekc.dev
helm repo update

helm upgrade --install sonarr-tv alekc/sonarr \
  --namespace media \
  -f sonarr/tv-custom-values.yaml

# Optional: Install Sonarr-Anime (separate instance for anime)
helm upgrade --install sonarr-anime alekc/sonarr \
  --namespace media \
  -f sonarr/anime-custom-values.yaml
```

**Verify:**
```bash
kubectl get pods -n media | grep sonarr
kubectl get ingress -n media | grep sonarr
```

**Details:** See [Sonarr README](sonarr/README.md).

---

#### Lidarr - Music Collection Manager

**What it does:** Automates music downloads and organization.

**Prerequisites:**
- NFS share for music
- qBittorrent installed
- Prowlarr configured
- Ingress with TLS

**Quick Start:**

```bash
# Use media namespace (created for Prowlarr)
# Create PV for music
kubectl apply -f lidarr/pv-music.yaml

helm repo add k8s-home-lab https://k8s-home-lab.github.io/helm-charts/
helm repo update

helm upgrade --install lidarr k8s-home-lab/lidarr \
  --namespace media \
  -f lidarr/custom-values.yaml
```

**Verify:**
```bash
kubectl get pods -n media | grep lidarr
kubectl get ingress -n media | grep lidarr
```

**Details:** See [Lidarr README](lidarr/README.md).

---

#### Seerr - Media Request Management (Overseerr fork)

**What it does:** User-friendly interface for requesting movies and TV shows (integrates with Radarr/Sonarr). The active fork of Overseerr; reuses the legacy `overseerr-config` PVC so no data migration is required.

**Prerequisites:**
- Radarr and Sonarr installed
- Plex or Jellyfin installed
- Ingress with TLS

**Quick Start:**

```bash
# Use media namespace (created for Prowlarr)
# Apply the Longhorn-backed PVC (preserves the original Overseerr volume)
kubectl apply -f media-automation/seerr/overseerr-config-pvc.yaml

helm repo add k8s-charts https://kriegalex.github.io/k8s-charts/
helm repo update

helm upgrade --install seerr k8s-charts/seerr-chart \
  --namespace media \
  -f media-automation/seerr/custom-values.yaml
```

**Verify:**
```bash
kubectl get pods -n media | grep seerr
kubectl get ingress -n media | grep seerr
```

**Details:** See [seerr README](media-automation/seerr/README.md).

---

### Downloads & Utilities

#### qBittorrent - Torrent Client with VPN

**What it does:** BitTorrent client with integrated VPN support (PIA, Proton VPN, etc.).

**Prerequisites:**
- VPN provider subscription (Private Internet Access or Proton VPN)
- VPN credentials
- NFS share for downloads
- Ingress with TLS

**Quick Start:**

```bash
# Use media namespace (created for Prowlarr)
# Create PV for downloads
kubectl apply -f qbittorrent/pv-downloads.yaml

# Create secrets with VPN credentials
cp qbittorrent/secrets-template-pia.yaml qbittorrent/secrets.yaml
# OR for Proton VPN:
# cp qbittorrent/secrets-template-proton.yaml qbittorrent/secrets.yaml
nano qbittorrent/secrets.yaml
kubectl apply -f qbittorrent/secrets.yaml

# Install qBittorrent
# Note: Check the README for the specific Helm repo and chart being used
helm upgrade --install qbittorrent <chart-repo>/<chart-name> \
  --namespace media \
  -f qbittorrent/custom-values-pia.yaml

# OR for Proton VPN:
# helm upgrade --install qbittorrent <chart-repo>/<chart-name> \
#   --namespace media \
#   -f qbittorrent/custom-values-proton.yaml
```

**Verify:**
```bash
kubectl get pods -n media | grep qbittorrent
kubectl get ingress -n media | grep qbittorrent

# Verify VPN is working (check IP from within pod)
kubectl exec -n media deployment/qbittorrent -- curl -s https://ifconfig.me
```

**Details:** See [qBittorrent README](qbittorrent/README.md) for VPN setup and troubleshooting.

---

#### FlareSolverr - Cloudflare Bypass

**What it does:** Proxy server to bypass Cloudflare protection for *arr applications.

**Prerequisites:**
- None (standalone utility)

**Quick Start:**

```bash
# Use media namespace (created for Prowlarr)
helm repo add k8s-home-lab-repo https://k8s-home-lab.github.io/helm-charts/
helm repo update

helm upgrade --install flaresolverr k8s-home-lab-repo/flaresolverr \
  --namespace media \
  -f flaresolverr/custom-values.yaml
```

**Verify:**
```bash
kubectl get pods -n media | grep flaresolverr
```

**Configure in Prowlarr/Radarr/Sonarr:**
- FlareSolverr URL: `http://flaresolverr.media.svc.cluster.local:8191`

**Details:** See [FlareSolverr README](flaresolverr/README.md).

---

### Development & Infrastructure

#### Gitea - Self-Hosted Git Service

**What it does:** Lightweight Git service (similar to GitHub/GitLab).

**Prerequisites:**
- CloudNativePG operator
- Storage provisioner
- Ingress with TLS

**Quick Start:**

```bash
# Create namespace
kubectl create namespace gitea

# Create PostgreSQL cluster
kubectl apply -f gitea/postgres-cluster.yaml

# Create PVs for Git repositories
kubectl apply -f gitea/pv-data.yaml

# Create secrets
cp gitea/secrets-template.yaml gitea/secrets.yaml
nano gitea/secrets.yaml
kubectl apply -f gitea/secrets.yaml

# Install Gitea
helm repo add k8s-charts https://kriegalex.github.io/k8s-charts/
helm repo update

helm upgrade --install gitea k8s-charts/gitea \
  --namespace gitea \
  -f gitea/custom-values.yaml
```

**Verify:**
```bash
kubectl get pods -n gitea
kubectl get ingress -n gitea
```

**Details:** See [Gitea README](gitea/README.md).

---

#### PostgreSQL - Database (Legacy)

**NOTE:** This section describes legacy standalone PostgreSQL. The recommended approach is using [CloudNativePG](database/cloudnative-pg/) for HA database clusters.

CloudNativePG provides:
- High availability with automatic failover
- Built-in backup and restore
- Connection pooling with PgBouncer
- Better integration with Kubernetes

See [CloudNativePG README](database/cloudnative-pg/README.md) for installation instructions.

---

#### Redis - Cache & Message Broker

**What it does:** In-memory data store for caching and message queuing.

**Prerequisites:**
- Storage provisioner (optional, for persistence)

**Quick Start:**

```bash
kubectl create namespace redis

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm upgrade --install redis bitnami/redis \
  --namespace redis \
  -f redis/custom-values.yaml
```

**Verify:**
```bash
kubectl get pods -n redis
```

**Details:** See [Redis README](redis/README.md).

---

### Game Servers

#### Palworld Server

**What it does:** Dedicated server for Palworld multiplayer game.

**Prerequisites:**
- Storage provisioner
- Sufficient resources (4GB RAM minimum)

**Quick Start:**

```bash
kubectl create namespace game-servers

# Create secrets if needed
cp palworld-server/secrets-template.yaml palworld-server/secrets.yaml
# Edit secrets.yaml with server settings
kubectl apply -f palworld-server/secrets.yaml

helm repo add k8s-charts https://kriegalex.github.io/k8s-charts/
helm repo update

helm upgrade --install palworld-server k8s-charts/palworld-server \
  --namespace game-servers \
  -f palworld-server/custom-values.yaml
```

**Verify:**
```bash
kubectl get pods -n game-servers
kubectl get svc -n game-servers
```

**Details:** See [Palworld Server README](palworld-server/README.md).

---

#### Satisfactory Server

**What it does:** Dedicated server for Satisfactory multiplayer game.

**Prerequisites:**
- Storage provisioner
- Sufficient resources (8GB RAM minimum)

**Quick Start:**

```bash
# Use game-servers namespace (created for Palworld)
helm repo add naj98 https://98jan.github.io/helm-charts/
helm repo update

helm upgrade --install satisfactory-server naj98/satisfactory \
  --namespace game-servers \
  -f satisfactory-server/custom-values.yaml
```

**Verify:**
```bash
kubectl get pods -n game-servers
kubectl get svc -n game-servers
```

**Details:** See [Satisfactory Server README](satisfactory-server/README.md).

---

### Network Services

#### Pi-hole - DNS & Ad-Blocking

**What it does:** Network-wide ad blocker and DNS server.

**Prerequisites:**
- Storage provisioner
- LoadBalancer or NodePort for DNS traffic

**Quick Start:**

```bash
kubectl create namespace pihole

# Create secrets
cp pihole/secrets-template.yaml pihole/secrets.yaml
nano pihole/secrets.yaml
kubectl apply -f pihole/secrets.yaml

helm repo add mojo2600 https://mojo2600.github.io/pihole-kubernetes/
helm repo update

helm upgrade --install pihole mojo2600/pihole \
  --namespace pihole \
  -f pihole/custom-values.yaml
```

**Verify:**
```bash
kubectl get pods -n pihole
kubectl get svc -n pihole
```

**Details:** See [Pi-hole README](pihole/README.md).

---

## Common Patterns

### Managing Secrets

All applications use Kubernetes secrets for sensitive data. Follow this pattern:

**1. Copy the template:**
```bash
cp <app>/secrets-template.yaml <app>/secrets.yaml
```

**2. Edit with actual values:**
```bash
nano <app>/secrets.yaml
```

**3. Apply the secret:**
```bash
kubectl apply -f <app>/secrets.yaml
```

**Generate secure passwords:**
```bash
# Generate 32-character password
openssl rand -base64 32

# Generate 16-character alphanumeric
openssl rand -hex 16
```

**Security best practices:**
- Never commit `secrets.yaml` to git (they're in .gitignore)
- Use strong, unique passwords for each application
- Rotate passwords periodically
- Use Sealed Secrets or External Secrets Operator for GitOps workflows

---

### Storage Provisioning

#### Dynamic PVC Creation (Longhorn/NFS)

Most applications use dynamic PVCs:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-app-data
  namespace: my-app
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 10Gi
```

Apply and the StorageClass will automatically create the PersistentVolume.

#### Manual PV/PVC Creation (NFS Shares)

For media applications (Plex, Radarr, Sonarr), create manual PVs pointing to NFS shares:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-movies
spec:
  capacity:
    storage: 1000Gi
  accessModes:
    - ReadWriteMany
  nfs:
    server: 192.168.1.100  # NFS server IP
    path: /mnt/media/movies
  storageClassName: ""

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-movies
  namespace: plex
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 1000Gi
  volumeName: pv-movies
```

**When to use each:**
- **Dynamic PVCs:** Application data, databases, configuration (Longhorn for HA)
- **Manual PV/PVC:** Large media libraries on NFS (movies, TV shows, music)

---

### Ingress Configuration

Basic ingress pattern for exposing applications:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: my-app
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    # Optional: force HTTP→HTTPS via the cluster-wide Traefik Middleware.
    # traefik.ingress.kubernetes.io/router.middlewares: "traefik-redirect-https@kubernetescrd"
spec:
  ingressClassName: traefik
  tls:
  - hosts:
    - app.yourdomain.com
    secretName: my-app-tls  # cert-manager creates this
  rules:
  - host: app.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              number: 80
```

**What happens:**
1. DNS resolves `app.yourdomain.com` to the Traefik LoadBalancer IP
2. Traefik routes traffic to `my-app` service
3. cert-manager automatically obtains and renews TLS certificate
4. Traffic is encrypted end-to-end

---

### Backup Setup

#### PVC Backups with k8up

Mark PVCs for backup using annotations:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-app-data
  namespace: my-app
  annotations:
    k8up.io/backup: "true"  # Enable backup for this PVC
spec:
  # ... PVC spec
```

Create a backup schedule:

```yaml
apiVersion: k8up.io/v1
kind: Schedule
metadata:
  name: schedule-backups
  namespace: my-app
spec:
  backend:
    repoPasswordSecretRef:
      name: backup-repo
      key: password
    s3:
      endpoint: https://s3.amazonaws.com
      bucket: my-backups
      accessKeyIDSecretRef:
        name: backup-repo
        key: username
      secretAccessKeySecretRef:
        name: backup-repo
        key: password
  backup:
    schedule: '0 2 * * *'  # Daily at 2 AM
    keepJobs: 7
  prune:
    schedule: '0 3 * * 0'  # Weekly on Sunday at 3 AM
    retention:
      keepDaily: 7
      keepWeekly: 4
      keepMonthly: 12
```

#### Database Backups with CloudNativePG

CloudNativePG clusters have built-in backup support. Enable S3 backups in cluster definition:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: my-app-db
spec:
  instances: 3
  backup:
    barmanObjectStore:
      destinationPath: s3://my-bucket/cnpg-backups/
      s3Credentials:
        accessKeyId:
          name: backup-credentials
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: backup-credentials
          key: ACCESS_SECRET_KEY
    retentionPolicy: "30d"
```

---

### Database Cluster Creation

CloudNativePG Cluster example with HA:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: my-app-postgres
  namespace: my-app
spec:
  instances: 3  # 1 primary + 2 standby replicas

  postgresql:
    parameters:
      max_connections: "200"
      shared_buffers: "256MB"

  storage:
    storageClass: longhorn
    size: 20Gi

  monitoring:
    enablePodMonitor: true

  backup:
    retentionPolicy: "30d"
    barmanObjectStore:
      destinationPath: s3://my-bucket/postgres-backups/
      s3Credentials:
        accessKeyId:
          name: postgres-backup-credentials
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: postgres-backup-credentials
          key: ACCESS_SECRET_KEY
```

**Connection details:**
- **Primary (read-write):** `my-app-postgres-rw.my-app.svc.cluster.local:5432`
- **Read-only replicas:** `my-app-postgres-ro.my-app.svc.cluster.local:5432`
- **Any instance:** `my-app-postgres-r.my-app.svc.cluster.local:5432`

---

## Troubleshooting

### Cluster Health Checks

```bash
# Check node status
kubectl get nodes
# All should show STATUS: Ready

# Check all pods
kubectl get pods -A
# Look for CrashLoopBackOff, Error, Pending

# Check PVCs
kubectl get pvc -A
# All should show STATUS: Bound
```

### Common Issues

#### 1. Pods Stuck in Pending

**Symptom:**
```bash
kubectl get pods -n my-app
# Shows STATUS: Pending
```

**Causes:**
- Insufficient resources (CPU/memory)
- Storage provisioner not working
- Node selector/affinity not satisfied

**Debug:**
```bash
kubectl describe pod <pod-name> -n <namespace>
# Check Events section for errors

# Check node resources
kubectl top nodes

# Check PVC status
kubectl get pvc -n <namespace>
```

**Solutions:**
- If storage issue: Verify Longhorn/NFS provisioner is running
- If resource issue: Scale down other apps or add nodes
- If scheduling issue: Check node labels and pod affinity

---

#### 2. Pods Stuck in CrashLoopBackOff

**Symptom:**
Pod repeatedly crashes and restarts.

**Debug:**
```bash
# Check pod logs
kubectl logs <pod-name> -n <namespace>

# Check previous container logs (if restarting)
kubectl logs <pod-name> -n <namespace> --previous

# Describe pod for events
kubectl describe pod <pod-name> -n <namespace>
```

**Common causes:**
- Missing or incorrect secrets
- Database connection failures
- Configuration errors
- Permission issues

**Solutions:**
- Verify secrets exist: `kubectl get secret -n <namespace>`
- Check database cluster is ready: `kubectl get cluster -n <namespace>`
- Review application logs for specific errors

---

#### 3. Ingress Not Accessible

**Symptom:**
Cannot access application via domain name.

**Debug:**
```bash
# Check ingress
kubectl get ingress -n <namespace>
# Should show ADDRESS (LoadBalancer IP)

# Check Traefik controller
kubectl get pods -n traefik
# Should be Running

# Check cert-manager certificates
kubectl get certificate -n <namespace>
# Should show READY: True
```

**Solutions:**
- **No ADDRESS:** Check MetalLB is running and has IP pool
- **DNS not resolving:** Verify DNS records point to LoadBalancer IP
- **Certificate issues:** Check cert-manager logs, verify ClusterIssuer is ready
- **502 Bad Gateway:** Backend service/pods not ready

---

#### 4. Database Connection Failures

**Symptom:**
Application cannot connect to PostgreSQL database.

**Debug:**
```bash
# Check CloudNativePG cluster
kubectl get cluster -n <namespace>
# Should show INSTANCES: 3, READY: 3

# Check database pods
kubectl get pods -n <namespace> | grep postgres

# Check database logs
kubectl logs <postgres-pod> -n <namespace>

# Test connection from another pod
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
  psql -h my-app-postgres-rw.my-app.svc.cluster.local -U app -d app
```

**Solutions:**
- Wait for cluster to be fully ready (may take 2-3 minutes after creation)
- Verify connection string uses correct service name
- Check database credentials in secrets

---

#### 5. Certificate Not Issuing

**Symptom:**
Ingress shows `default-fake-certificate` or TLS errors.

**Debug:**
```bash
# Check certificate status
kubectl get certificate -n <namespace>
kubectl describe certificate <cert-name> -n <namespace>

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Check DNS challenge (for DNS-01)
kubectl get challenge -n <namespace>
kubectl describe challenge <challenge-name> -n <namespace>
```

**Solutions:**
- **Pending too long:** DNS not propagating (wait 5-10 minutes)
- **DNS provider errors:** Verify API credentials in secrets
- **Rate limit:** Use staging ClusterIssuer for testing
- **Webhook errors:** Reinstall DNS provider webhook (e.g., Infomaniak)

See [cert-manager README](ingress/cert-manager/README.md) for detailed troubleshooting.

---

#### 6. Volume Attachment Issues (Longhorn)

**Symptom:**
Pod stuck in `ContainerCreating` with volume attachment errors.

**Debug:**
```bash
# Check volume attachment
kubectl get volumeattachment

# Check Longhorn volume status
kubectl get volumes -n longhorn-system

# Check Longhorn manager logs
kubectl logs -n longhorn-system -l app=longhorn-manager
```

**Solutions:**
- Verify `open-iscsi` is installed and running on nodes
- Restart instance manager pods if failed
- Check node disk space (Longhorn UI or kubectl)

See [Longhorn README](storage/longhorn/README.md) for detailed troubleshooting.

---

### Component-Specific Troubleshooting

For detailed troubleshooting of specific components, see their READMEs:

- **Ingress issues:** [Traefik README](ingress/traefik/README.md)
- **Certificate issues:** [cert-manager README](ingress/cert-manager/README.md)
- **Storage issues:** [Longhorn README](storage/longhorn/README.md)
- **Database issues:** [CloudNativePG README](database/cloudnative-pg/README.md)
- **Backup issues:** [k8up README](backup/k8up/README.md)
- **Monitoring issues:** [Monitoring README](monitoring/README.md)

---

## Next Steps

### 1. Set Up Monitoring

After deploying applications, configure monitoring:

1. Access Grafana dashboard
2. Import community dashboards for your applications
3. Set up alerting for critical services
4. Monitor resource usage trends

### 2. Configure Backups

Ensure your data is protected:

1. Enable k8up backups for critical PVCs
2. Configure CloudNativePG backups for databases
3. Test restore procedures
4. Set up backup monitoring/alerting

### 3. Harden Security

Improve security posture:

1. Enable network policies (if using Calico/Cilium)
2. Set up OAuth2 proxy for sensitive applications
3. Implement RBAC for cluster access
4. Regularly update applications and Helm charts
5. Rotate secrets periodically

### 4. Optimize Performance

Tune your cluster for better performance:

1. Adjust replica counts based on load
2. Configure resource requests/limits
3. Enable caching (Redis) where appropriate
4. Optimize database queries
5. Monitor and address bottlenecks

### 5. Join the Community

Get help and share your experience:

- GitHub Issues: [k8s-homelab Issues](https://github.com/kriegalex/k8s-homelab/issues)
- Kubernetes Community: https://kubernetes.io/community/
- Homelab subreddit: https://reddit.com/r/homelab
- Self-Hosted Community: https://reddit.com/r/selfhosted

---

## Additional Resources

### Official Documentation

- **Kubernetes:** https://kubernetes.io/docs/
- **Helm:** https://helm.sh/docs/
- **k3s:** https://docs.k3s.io/

### Homelab Resources

- **k3s-ansible:** https://github.com/kriegalex/k3s-ansible
- **Awesome Selfhosted:** https://github.com/awesome-selfhosted/awesome-selfhosted
- **Homelab Wiki:** https://wiki.r-selfhosted.com/

### Learning Resources

- **Kubernetes by Example:** https://kubernetesbyexample.com/
- **Kubernetes the Hard Way:** https://github.com/kelseyhightower/kubernetes-the-hard-way
- **Helm Best Practices:** https://helm.sh/docs/chart_best_practices/

---

## Conclusion

You now have a complete guide to deploying a production-ready Kubernetes homelab stack!

**Deployment Summary:**

1. ✅ **Cluster provisioning** → Use k3s-ansible
2. ✅ **Infrastructure** → Deploy ingress, storage, database, backup, monitoring
3. ✅ **Applications** → Deploy productivity, media, development, and game server apps
4. ✅ **Monitoring** → Set up Prometheus/Grafana
5. ✅ **Backups** → Configure k8up and database backups
6. ✅ **Security** → Harden cluster and applications

**Maintenance:**
- Update Helm charts regularly
- Monitor resource usage
- Test backup restores
- Review logs for errors
- Plan for growth

**Need help?** Check component READMEs for detailed documentation, or open an issue on GitHub.

Happy homelabbing! 🏠🖥️
