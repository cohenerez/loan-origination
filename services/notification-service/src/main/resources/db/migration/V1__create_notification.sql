-- One row per loan event; the unique event_uuid makes the consumer idempotent.
CREATE TABLE notification (
    id          UUID                     PRIMARY KEY,
    event_uuid  VARCHAR(64)              NOT NULL,
    loan_id     VARCHAR(18)              NOT NULL,
    new_status  VARCHAR(40)              NOT NULL,
    recipient   VARCHAR(254),
    subject     VARCHAR(200),
    body        VARCHAR(4000),
    status      VARCHAR(10)              NOT NULL,
    attempts    INTEGER                  NOT NULL,
    last_error  VARCHAR(500),
    created_at  TIMESTAMP WITH TIME ZONE NOT NULL,
    sent_at     TIMESTAMP WITH TIME ZONE,
    CONSTRAINT uq_notification_event_uuid UNIQUE (event_uuid),
    CONSTRAINT ck_notification_status CHECK (status IN ('SENT', 'SKIPPED', 'FAILED'))
);

CREATE INDEX ix_notification_loan_created ON notification (loan_id, created_at DESC);
