package com.erez.loans.bridge.kafka;

import java.math.BigDecimal;

/**
 * A loan status change as published to Kafka. Mirrors LoanStatusChanged__e.
 *
 * @param eventUuid  unique per change, set by Salesforce; consumers use it to drop duplicates
 * @param occurredAt ISO-8601 time the event was published in Salesforce
 * @param replayId   Base64 Pub/Sub replay ID, kept for tracing
 */
public record LoanStatusEvent(
        String eventUuid,
        String loanId,
        String oldStatus,
        String newStatus,
        BigDecimal amount,
        String applicantEmail,
        String occurredAt,
        String replayId) {
}
