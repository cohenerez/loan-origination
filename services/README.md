# Backend services

| Service                                      | Port       | Role                                                         |
| -------------------------------------------- | ---------- | ------------------------------------------------------------ |
| [credit-scoring](credit-scoring)             | 8080       | REST API Salesforce calls to score applications              |
| [event-bridge](event-bridge)                 | 8085, 8086 | Salesforce Pub/Sub API → Kafka (2 instances, active/standby) |
| [notification-service](notification-service) | 8082       | Kafka → emails to applicants                                 |
| PostgreSQL                                   | 5432       | `scoring`, `notifications` and `bridge` databases            |
| Kafka (KRaft)                                | 9094       | `loan-events`, `loan-events.DLT`                             |
| Mailpit                                      | 8025       | Inbox for every email sent in development                    |
| Kafka UI                                     | 8090       | Browse topics and messages                                   |

## Run everything

```bash
cp .env.example .env        # fill in SF_LOGIN_URL, SF_CLIENT_ID, SF_CLIENT_SECRET (see event-bridge/README.md)
docker compose up -d --build
docker compose ps           # all services healthy
```

## End-to-end check

1. In Salesforce, move a loan with an applicant email from Draft to **Submitted**.
2. Bridge log (`docker compose logs -f event-bridge`): `Forwarded loan ... Draft -> Submitted`.
3. Kafka UI (http://localhost:8090) → topic `loan-events`: the JSON message, key = loan ID.
4. Mailpit (http://localhost:8025): the "We received your loan application" email.
5. `curl -s 'localhost:8082/api/v1/notifications?loanId=<record id>'`: the stored notification.

Ports are bound to localhost only. On a server, expose only credit-scoring, behind HTTPS.

## Deploying to a server

On an Ubuntu VM with Docker (an Oracle Cloud Always Free Ampere A1 instance with 2 OCPU and 12 GB
is enough), `docker-compose.prod.yml` adds [Caddy](https://caddyserver.com) as the only public
entry point. Caddy gets a Let's Encrypt certificate for `PUBLIC_HOST` and forwards just
`/api/v1/*` and `/actuator/health` to credit scoring; it also sets memory limits for every container.

```bash
git clone https://github.com/cohenerez/loan-origination.git
cd loan-origination/services
cp .env.example .env    # strong SCORING_API_KEY and DB_PASSWORD, PUBLIC_HOST, SF_* values
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

Open TCP 80 and 443 both in the VCN security list and in the VM's own firewall
(`iptables` on Oracle's Ubuntu images). Then set the `Credit_Scoring` Named Credential URL to
`https://<PUBLIC_HOST>` and the External Credential's API key to the server's `SCORING_API_KEY`.

Kafka UI and Mailpit stay on the server's localhost. Reach them through an SSH tunnel:

```bash
ssh -i ~/.ssh/<key> -L 8090:localhost:8090 -L 8025:localhost:8025 ubuntu@<server-ip>
```
