-- Last replay ID safely forwarded to Kafka, per subscription (topic).
-- Written only by the instance holding the leader lock.
CREATE TABLE bridge_checkpoint (
    subscription_id VARCHAR(100)             PRIMARY KEY,
    replay_id       VARCHAR(500)             NOT NULL,
    updated_at      TIMESTAMP WITH TIME ZONE NOT NULL
);
