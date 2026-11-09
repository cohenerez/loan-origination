package com.erez.loans.notifications.api;

import com.erez.loans.notifications.domain.Notification;
import java.time.Instant;

public record NotificationView(
        String eventUuid,
        String loanId,
        String newStatus,
        String status,
        String recipient,
        String subject,
        int attempts,
        String lastError,
        Instant createdAt,
        Instant sentAt) {

    static NotificationView of(Notification n) {
        return new NotificationView(n.getEventUuid(), n.getLoanId(), n.getNewStatus(), n.getStatus().name(),
                n.getRecipient(), n.getSubject(), n.getAttempts(), n.getLastError(), n.getCreatedAt(), n.getSentAt());
    }
}
