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

PostgreSQL runs as its own user (uid 999) under the runtime's default seccomp filter, with
k3s's AppArmor profile turned off for that pod only (see [Why PostgreSQL is AppArmor-unconfined](#why-postgresql-is-apparmor-unconfined)).

Memory limits match `docker-compose.prod.yml`. The services read the Kubernetes probes from Spring
Boot Actuator (`/actuator/health/liveness` and `/readiness`), which Spring Boot turns on
automatically when it runs on Kubernetes.

## Install

On the VM, from the repository root. The Compose stack and k3s both want ports 80 and 443, so
stop Compose first (`down` without `-v` keeps its volumes, so you can go back).

**Before you start:** `kubectl create secret --from-env-file` keeps quotes as part of the value
(Docker Compose strips them). Remove the quotes from any quoted line in `.env`, for example
`MAIL_FROM=Erez Bank <loans@erez.tech>`. Compose reads the unquoted form the same way.

```bash
grep -n '"' services/.env       # should print nothing
```

```bash
cd services
# Optional: keep the existing data
mkdir -p ~/backups
for db in scoring notifications bridge; do
  docker compose exec -T postgres pg_dump -U scoring -Fc "$db" > ~/backups/"$db".dump
done
docker compose -f docker-compose.yml -f docker-compose.prod.yml down
cd ..

# 1. Let the k3s pod (10.42.0.0/16) and service (10.43.0.0/16) networks through Oracle's
#    default iptables rules, which otherwise reject traffic between pods
sudo iptables -I INPUT -s 10.42.0.0/16 -j ACCEPT
sudo iptables -I INPUT -s 10.43.0.0/16 -j ACCEPT
sudo iptables -I FORWARD -s 10.42.0.0/16 -j ACCEPT
sudo iptables -I FORWARD -d 10.42.0.0/16 -j ACCEPT
sudo netfilter-persistent save

# 2. k3s, without Traefik (Caddy is the entry point)
curl -sfL https://get.k3s.io | sh -s - --disable traefik --write-kubeconfig-mode 644
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 3. Service images, built on the VM (arm64) and loaded into k3s
services/k8s/build-images.sh

# 4. Secrets from the existing .env
kubectl create namespace loan-origination
kubectl -n loan-origination create secret generic loan-secrets --from-env-file=services/.env

# 5. Everything else
kubectl apply -k services/k8s
kubectl -n loan-origination get pods -w     # wait until all pods are Running and Ready
```

If you saved data, restore it with the three services stopped. The bridges then resume from the
saved replay checkpoint, and no event from the migration window is lost (Salesforce keeps
Platform Events for 72 hours):

```bash
kubectl -n loan-origination scale deployment credit-scoring event-bridge notification-service --replicas=0
for db in scoring notifications bridge; do
  kubectl -n loan-origination exec -i postgres-0 -- pg_restore -U scoring -d "$db" --clean --if-exists < ~/backups/"$db".dump
done
kubectl -n loan-origination scale deployment credit-scoring notification-service --replicas=1
kubectl -n loan-origination scale deployment event-bridge --replicas=2
```

Caddy starts with an empty certificate volume and gets a new Let's Encrypt certificate on its
first request, which takes a few seconds.

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

## Why PostgreSQL is AppArmor-unconfined

On this VM (Ubuntu, kernel 7.0, k3s 1.37) PostgreSQL never became ready under k3s, while the same
image ran fine under Docker Compose:

1. The container sat at 100% CPU in `gosu`, the image's root-to-postgres user switch, with no log output at all.
2. Started directly as uid 999, PostgreSQL got further but stalled: new connections and autovacuum workers never started, shutdowns never finished, and the liveness probe kept killing it.
3. The log finally showed `could not signal for checkpoint: Permission denied`: one PostgreSQL process could not signal another of the same user in the same container.
4. `sudo dmesg | grep 'apparmor="DENIED"'` showed why: `operation="signal" profile="cri-containerd.apparmor.d" ... peer="cri-containerd.apparmor.d//&unconfined"`.

The AppArmor profile that k3s's containerd applies to every container denies signals between the
container's own processes on this kernel. Docker's profile allows them. PostgreSQL relies on such
signals (checkpoints, new connections, shutdown), and so does the Go runtime in `gosu`; the JVM
services and Kafka don't, which is why only PostgreSQL broke.

`postgres.yaml` therefore sets `appArmorProfile: Unconfined` for that pod only, and keeps it
confined otherwise: `seccompProfile: RuntimeDefault`, uid 999 instead of root. A startup probe gives
first-time setup and crash recovery up to 5 minutes before liveness checks begin.

## Troubleshooting

- **A pod hangs with no logs, or reports `Permission denied` for something harmless.** Check
  `sudo dmesg | grep 'apparmor="DENIED"'` for the same kind of denial as above.

- **Pods can't reach each other, or 443 doesn't answer.** Check that the rules from step 1 are
  still there (`sudo iptables -L INPUT -n | head`) and that 80 and 443 are open in the VCN
  security list. Port 6443 (the Kubernetes API) must stay closed there.
- **An email arrives from `"Erez Bank <...>"` with quotes, or not at all.** A quoted value in
  `.env`: remove the quotes and recreate the secret (see Day to day).
- **A service pod restarts during startup.** It probably can't reach PostgreSQL or Kafka yet; it
  recovers once they are ready. `kubectl -n loan-origination describe pod <name>` shows why.
- **Go back to Compose:** `sudo /usr/local/bin/k3s-uninstall.sh`, then start Compose as before.
