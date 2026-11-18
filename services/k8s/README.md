# Kubernetes deployment (k3s on Oracle Cloud)

The same backend as `docker-compose.yml` + `docker-compose.prod.yml`, as Kubernetes manifests.
It runs on [k3s](https://k3s.io), a lightweight Kubernetes distribution, on the same Oracle Cloud
Always Free Ampere A1 VM, so it still costs nothing.

| Compose service      | Kubernetes                                                            |
| -------------------- | --------------------------------------------------------------------- |
| postgres             | StatefulSet + 5 Gi volume, init script in a ConfigMap                 |
| kafka (KRaft)        | StatefulSet + 5 Gi volume                                             |
| credit-scoring       | Deployment + Service, startup/liveness/readiness probes               |
| event-bridge (×2)    | Deployment with 2 replicas (leader + standby via advisory lock)       |
| notification-service | Deployment + Service, Mailpit defaults in a ConfigMap                 |
| caddy                | Deployment + LoadBalancer Service on ports 80/443, certificate volume |
| mailpit, kafka-ui    | Deployments, reachable only through `kubectl port-forward`            |
| `.env`               | Secret `loan-secrets`, created from the same file                     |

Memory limits match `docker-compose.prod.yml`. The services read the Kubernetes probes from Spring
Boot Actuator (`/actuator/health/liveness` and `/readiness`), which Spring Boot turns on
automatically when it runs on Kubernetes.

## Install

On the VM, from the repository root. The Compose stack and k3s both want ports 80 and 443, so
stop Compose first (`down` without `-v` keeps its volumes, so you can go back).

```bash
cd services
# Optional: keep the existing data
for db in scoring notifications bridge; do
  docker compose exec -T postgres pg_dump -U scoring -Fc "$db" > "/tmp/$db.dump"
done
docker compose -f docker-compose.yml -f docker-compose.prod.yml down
cd ..

# 1. k3s, without Traefik (Caddy is the entry point)
curl -sfL https://get.k3s.io | sh -s - --disable traefik --write-kubeconfig-mode 644
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 2. Service images, built on the VM (arm64) and loaded into k3s
services/k8s/build-images.sh

# 3. Secrets from the existing .env
kubectl create namespace loan-origination
kubectl -n loan-origination create secret generic loan-secrets --from-env-file=services/.env

# 4. Everything else
kubectl apply -k services/k8s
kubectl -n loan-origination get pods -w     # wait until all pods are Running and Ready
```

Restore the data you saved, if any, then restart the services so they pick it up:

```bash
for db in scoring notifications bridge; do
  kubectl -n loan-origination exec -i postgres-0 -- pg_restore -U scoring -d "$db" --clean --if-exists < "/tmp/$db.dump"
done
kubectl -n loan-origination rollout restart deployment credit-scoring event-bridge notification-service
```

## Check

```bash
curl -s https://<PUBLIC_HOST>/actuator/health                       # {"status":"UP"} through Caddy
kubectl -n loan-origination logs -l app=event-bridge --tail=20       # one leader, one standby
kubectl -n loan-origination port-forward svc/kafka-ui 8090:8080      # http://localhost:8090
kubectl -n loan-origination port-forward svc/mailpit 8025            # http://localhost:8025
```

The Salesforce Named Credential keeps the same URL (`https://<PUBLIC_HOST>`) and API key.

## Day to day

```bash
# After a code change
services/k8s/build-images.sh
kubectl -n loan-origination rollout restart deployment credit-scoring event-bridge notification-service

# After changing .env
kubectl -n loan-origination create secret generic loan-secrets --from-env-file=services/.env \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n loan-origination rollout restart deployment
```

## Troubleshooting

- **Pods can't reach each other, or 443 doesn't answer.** Oracle's Ubuntu images ship an
  `iptables` rule that rejects most incoming traffic. Allow the k3s pod and service networks:
  `sudo iptables -I INPUT -s 10.42.0.0/16 -j ACCEPT && sudo iptables -I INPUT -s 10.43.0.0/16 -j ACCEPT`,
  then save the rules with `sudo netfilter-persistent save`.
- **A service pod restarts during startup.** It probably can't reach PostgreSQL or Kafka yet; it
  recovers once they are ready. `kubectl -n loan-origination describe pod <name>` shows why.
- **Go back to Compose:** `sudo /usr/local/bin/k3s-uninstall.sh`, then start Compose as before.
