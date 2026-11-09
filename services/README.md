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
