# Game Servers

This directory contains Kubernetes deployments for dedicated game servers.

## Applications

- **[palworld-server](palworld-server/)** - Palworld dedicated server
- **[satisfactory-server](satisfactory-server/)** - Satisfactory dedicated server

## Architecture

Game servers are deployed as StatefulSets with persistent storage for:

- World saves and game data
- Server configuration files
- Player progress and builds

### Networking

Game servers require specific port configurations:

- **LoadBalancer** service type for external access
- **MetalLB** IP assignment from pool (10.0.1.2-10.0.1.254)
- **Port forwarding** on home router to assigned LoadBalancer IP

## Installation

Each game server requires:

1. **Persistent storage** - Created via hostPath or Longhorn PVCs
2. **Secrets** - Game-specific credentials (server passwords, admin passwords)
3. **Helm deployment** - Using custom values for configuration
4. **Port forwarding** - External access via home router

### Storage Setup

Game servers use dedicated persistent volumes:

```bash
# Palworld example
sudo mkdir -p /mnt/palworld-server/data
sudo chown -R 1000:1000 /mnt/palworld-server/

# Satisfactory example
sudo mkdir -p /mnt/satisfactory-server/config
sudo chown -R 1000:1000 /mnt/satisfactory-server/
```

**Note**: You need to run these commands manually (requires sudo privileges).

### Secrets Management

Create secrets from templates:

```bash
# Palworld
kubectl create secret generic palworld-server-secret \
  --from-file=palworld-server/secrets-template.yaml

# Satisfactory (if applicable)
kubectl create secret generic satisfactory-server-secret \
  --from-literal=admin-password='your-password'
```

## Port Requirements

### Palworld Server

- **8211/UDP** - Game port
- **27015/UDP** - Query port (Steam)

Ensure these ports are forwarded from your router to the LoadBalancer IP.

### Satisfactory Server

- **7777/UDP** - Game port
- **15000/UDP** - Beacon port
- **15777/UDP** - Query port

Ensure these ports are forwarded from your router to the LoadBalancer IP.

## Configuration

### Resource Requirements

Game servers are resource-intensive:

- **CPU**: 2-4 cores minimum
- **Memory**: 4-8GB RAM minimum
- **Storage**: 10-50GB depending on world size

Configure resource limits in `custom-values.yaml` to prevent server lag.

### Backup Strategy

Game servers benefit from regular backups:

- Use [k8up](../backup/k8up/) for automated PVC backups
- Manual backups via `kubectl cp` for critical saves
- Test restore procedures before disaster strikes

## Operational Notes

### Server Updates

Most game server Helm charts support automatic updates:

```bash
helm repo update
helm upgrade <release-name> <chart> -f custom-values.yaml
```

Check release notes for breaking changes or required migrations.

### Performance Monitoring

Monitor server performance:

```bash
kubectl top pod -n game-servers
kubectl logs -n game-servers <pod-name>
```

### Restarting Servers

Restart servers for maintenance or configuration changes:

```bash
kubectl rollout restart statefulset/<release-name> -n game-servers
```

## Troubleshooting

### Server Not Accessible

1. Check LoadBalancer IP assignment:
   ```bash
   kubectl get svc -n game-servers
   ```

2. Verify port forwarding on router points to LoadBalancer IP

3. Check pod status:
   ```bash
   kubectl get pods -n game-servers
   kubectl describe pod <pod-name> -n game-servers
   ```

### Persistent Connection Issues

- Verify MetalLB IP pool configuration
- Check firewall rules on worker nodes
- Ensure ports are not blocked by ISP

### World Corruption

- Restore from backup immediately
- Check disk space on worker nodes
- Review pod logs for crash errors

## Documentation

Each game server directory contains:

- **README.md** - Installation and configuration guide
- **custom-values.yaml** - Helm value overrides
- **secrets-template.yaml** - Secret configuration template

Navigate to individual game server folders for detailed instructions.

## Future Additions

Consider adding other game servers:

- Minecraft
- Valheim
- ARK: Survival Evolved
- Terraria
- 7 Days to Die

Follow the same pattern: dedicated namespace, persistent storage, LoadBalancer service, port forwarding.
