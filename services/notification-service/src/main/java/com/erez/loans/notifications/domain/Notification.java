package com.erez.loans.notifications.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;


@Entity
@Table(name = "notification")
public class Notification {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "event_uuid", nullable = false, unique = true, length = 64)
    private String eventUuid;

    @Column(name = "loan_id", nullable = false, length = 18)
    private String loanId;

    @Column(name = "new_status", nullable = false, length = 40)
    private String newStatus;

    @Column(length = 254)
    private String recipient;

    @Column(length = 200)
    private String subject;

    @Column(length = 4000)
    private String body;

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.VARCHAR)
    @Column(nullable = false, length = 10)
    private NotificationStatus status;

    @Column(nullable = false)
    private int attempts;

    @Column(name = "last_error", length = 500)
    private String lastError;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "sent_at")
    private Instant sentAt;

    protected Notification() {
        // for JPA
    }

    public Notification(String eventUuid, String loanId, String newStatus, Instant createdAt) {
        this.eventUuid = eventUuid;
        this.loanId = loanId;
        this.newStatus = newStatus;
        this.createdAt = createdAt;
        this.status = NotificationStatus.FAILED;
    }

    public void sent(String recipient, String subject, String body, Instant at) {
        this.recipient = recipient;
        this.subject = subject;
        this.body = body;
        this.status = NotificationStatus.SENT;
        this.sentAt = at;
        this.lastError = null;
        this.attempts++;
    }

    public void skipped(String reason) {
        this.status = NotificationStatus.SKIPPED;
        this.lastError = reason;
    }

    public void failed(String recipient, String subject, String error) {
        this.recipient = recipient;
        this.subject = subject;
        this.status = NotificationStatus.FAILED;
        this.lastError = error == null ? null : error.substring(0, Math.min(error.length(), 500));
        this.attempts++;
    }

    public boolean isDone() {
        return status == NotificationStatus.SENT || status == NotificationStatus.SKIPPED;
    }

    public UUID getId() { return id; }
    public String getEventUuid() { return eventUuid; }
    public String getLoanId() { return loanId; }
    public String getNewStatus() { return newStatus; }
    public String getRecipient() { return recipient; }
    public String getSubject() { return subject; }
    public String getBody() { return body; }
    public NotificationStatus getStatus() { return status; }
    public int getAttempts() { return attempts; }
    public String getLastError() { return lastError; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getSentAt() { return sentAt; }
}
