package com.erez.loans.notifications.messaging;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import java.math.BigDecimal;

/** A loan status change, as published by the event bridge. Unknown fields are ignored for forward compatibility. */
@JsonIgnoreProperties(ignoreUnknown = true)
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
