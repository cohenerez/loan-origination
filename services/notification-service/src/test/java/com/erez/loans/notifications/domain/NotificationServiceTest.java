package com.erez.loans.notifications.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.reset;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

import com.erez.loans.notifications.messaging.LoanStatusEvent;
import java.math.BigDecimal;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.mail.MailSendException;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:notifications;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1",
        "spring.datasource.username=sa",
        "spring.datasource.password=",
        "spring.kafka.listener.auto-startup=false",
        "spring.kafka.admin.auto-create=false"
})
class NotificationServiceTest {

    @Autowired
    private NotificationService service;

    @Autowired
    private NotificationRepository repository;

    @MockitoBean
    private JavaMailSender mailSender;

    @BeforeEach
    void resetMail() {
        reset(mailSender);
    }

    private static LoanStatusEvent event(String newStatus, String email) {
        return new LoanStatusEvent(UUID.randomUUID().toString(), "a01di00001O3s0jAAB", "Scoring", newStatus,
                new BigDecimal("30000"), email, "2026-11-06T10:00:00Z", "cmVwbGF5");
    }

    @Test
    void sendsTheEmailAndRecordsIt() {
        LoanStatusEvent event = event("Approved", "noam@example.com");

        assertThat(service.handle(event)).isEqualTo(NotificationStatus.SENT);

        ArgumentCaptor<SimpleMailMessage> mail = ArgumentCaptor.forClass(SimpleMailMessage.class);
        verify(mailSender).send(mail.capture());
        assertThat(mail.getValue().getTo()).containsExactly("noam@example.com");
        assertThat(mail.getValue().getSubject()).isEqualTo("Your loan of $30,000 is approved");

        Notification saved = repository.findByEventUuid(event.eventUuid()).orElseThrow();
        assertThat(saved.getStatus()).isEqualTo(NotificationStatus.SENT);
        assertThat(saved.getAttempts()).isEqualTo(1);
        assertThat(saved.getSentAt()).isNotNull();
    }

    @Test
    void aDuplicateEventIsNotEmailedTwice() {
        LoanStatusEvent event = event("Funded", "tamar@example.com");

        service.handle(event);
        assertThat(service.handle(event)).isEqualTo(NotificationStatus.SENT);

        verify(mailSender, times(1)).send(any(SimpleMailMessage.class));
    }

    @Test
    void internalStatusesAreRecordedButNotSent() {
        LoanStatusEvent event = event("Scoring", "dana@example.com");

        assertThat(service.handle(event)).isEqualTo(NotificationStatus.SKIPPED);

        verify(mailSender, never()).send(any(SimpleMailMessage.class));
        assertThat(repository.findByEventUuid(event.eventUuid()).orElseThrow().getLastError())
                .contains("No customer email");
    }

    @Test
    void applicationsWithoutAnEmailAreSkipped() {
        LoanStatusEvent event = event("Approved", null);

        assertThat(service.handle(event)).isEqualTo(NotificationStatus.SKIPPED);

        verify(mailSender, never()).send(any(SimpleMailMessage.class));
    }

    @Test
    void aFailedSendIsRecordedAndRetriedSuccessfully() {
        LoanStatusEvent event = event("Submitted", "maya@example.com");
        doThrow(new MailSendException("SMTP down")).when(mailSender).send(any(SimpleMailMessage.class));

        assertThatThrownBy(() -> service.handle(event)).isInstanceOf(NotificationDeliveryException.class);
        Notification failed = repository.findByEventUuid(event.eventUuid()).orElseThrow();
        assertThat(failed.getStatus()).isEqualTo(NotificationStatus.FAILED);
        assertThat(failed.getLastError()).contains("SMTP down");

        reset(mailSender);
        assertThat(service.handle(event)).isEqualTo(NotificationStatus.SENT);
        Notification sent = repository.findByEventUuid(event.eventUuid()).orElseThrow();
        assertThat(sent.getAttempts()).isEqualTo(2);
        assertThat(sent.getLastError()).isNull();
    }

    @Test
    void malformedEventsAreIgnored() {
        LoanStatusEvent noUuid = new LoanStatusEvent(null, "a01", null, "Approved", null, "x@example.com", null, null);

        assertThat(service.handle(noUuid)).isEqualTo(NotificationStatus.SKIPPED);
        verify(mailSender, never()).send(any(SimpleMailMessage.class));
    }
}
