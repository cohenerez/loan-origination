-- Every scoring decision, kept for audit and used as the idempotency store (unique request_id).
CREATE TABLE credit_score (
    id               UUID                     PRIMARY KEY,
    request_id       VARCHAR(64)              NOT NULL,
    loan_id          VARCHAR(18)              NOT NULL,
    amount           NUMERIC(16, 2)           NOT NULL,
    term_months      INTEGER                  NOT NULL,
    monthly_income   NUMERIC(16, 2)           NOT NULL,
    purpose          VARCHAR(40),
    score            INTEGER                  NOT NULL,
    risk_tier        VARCHAR(1)               NOT NULL,
    monthly_payment  NUMERIC(16, 2)           NOT NULL,
    debt_to_income   NUMERIC(12, 4)           NOT NULL,
    reasons          VARCHAR(2000)            NOT NULL,
    model_version    VARCHAR(20)              NOT NULL,
    scored_at        TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT uq_credit_score_request_id UNIQUE (request_id),
    CONSTRAINT ck_credit_score_score CHECK (score BETWEEN 300 AND 850),
    CONSTRAINT ck_credit_score_risk_tier CHECK (risk_tier IN ('A', 'B', 'C', 'D'))
);

CREATE INDEX ix_credit_score_loan_scored_at ON credit_score (loan_id, scored_at DESC);
