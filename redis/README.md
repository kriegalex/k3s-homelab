# Redis

## Persistence

```console
kubectl create -f redis-master-pvc.yaml
```

## Installation

(optional) Inspect & modify the default values :

```console
helm show values oci://registry-1.docker.io/bitnamicharts/redis > custom-values.yaml
```

```console
helm upgrade --install redis oci://registry-1.docker.io/bitnamicharts/redis -f custom-values.yaml
```

### Post-installation message

```
Redis&reg; can be accessed via port 6379 on the following DNS name from within your cluster:

    redis-master.default.svc.cluster.local



To get your password run:

    export REDIS_PASSWORD=$(kubectl get secret --namespace default redis -o jsonpath="{.data.redis-password}" | base64 -d)

To connect to your Redis&reg; server:

1. Run a Redis&reg; pod that you can use as a client:

   kubectl run --namespace default redis-client --restart='Never'  --env REDIS_PASSWORD=$REDIS_PASSWORD  --image docker.io/bitnami/redis:7.2.5-debian-12-r4 --command -- sleep infinity

   Use the following command to attach to the pod:

   kubectl exec --tty -i redis-client \
   --namespace default -- bash

2. Connect using the Redis&reg; CLI:
   REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli -h redis-master

To connect to your database from outside the cluster execute the following commands:

    kubectl port-forward --namespace default svc/redis-master 6379:6379 &
    REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli -h 127.0.0.1 -p 6379
```