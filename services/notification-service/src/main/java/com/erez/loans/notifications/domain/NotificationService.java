package com.erez.loans.notifications.domain;

import com.erez.loans.notifications.config.NotificationProperties;
import com.erez.loans.notifications.messaging.LoanStatusEvent;
import java.time.Clock;
import java.time.Instant;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.mail.MailException;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;


@Service
public class NotificationService {

    private static final Logger log = LoggerFactory.getLogger(NotificationService.class);

    private final NotificationRepository repository;
    private final NotificationTemplates templates;
    private final JavaMailSender mailSender;
    private final NotificationProperties properties;
    private final Clock clock;

    public NotificationService(NotificationRepository repository, NotificationTemplates templates,JavaMailSender mailSender, NotificationProperties properties, Clock clock) {
        this.repository = repository;
        this.templates = templates;
        this.mailSender = mailSender;
        this.properties = properties;
        this.clock = clock;
    }

    public NotificationStatus handle(LoanStatusEvent event) {
        if (!StringUtils.hasText(event.eventUuid()) || !StringUtils.hasText(event.loanId())) {
            log.warn("Ignoring event without eventUuid or loanId: {}", event);
            return NotificationStatus.SKIPPED;
        }

        Notification notification = repository.findByEventUuid(event.eventUuid()).orElse(null);
        if (notification != null && notification.isDone()) {
            log.info("Event {} already handled ({}); skipping duplicate", event.eventUuid(), notification.getStatus());
            return notification.getStatus();
        }
        if (notification == null) {
            notification = new Notification(event.eventUuid(), event.loanId(),
                    event.newStatus() == null ? "unknown" : event.newStatus(), Instant.now(clock));
        }

        Optional<EmailMessage> message = templates.forEvent(event);
        if (message.isEmpty()) {
            notification.skipped("No customer email for status " + event.newStatus());
            repository.save(notification);
            return NotificationStatus.SKIPPED;
        }
        if (!StringUtils.hasText(event.applicantEmail())) {
            notification.skipped("Application has no applicant email");
            repository.save(notification);
            return NotificationStatus.SKIPPED;
        }

        EmailMessage email = message.get();
        try {
            SimpleMailMessage mail = new SimpleMailMessage();
            mail.setFrom(properties.fromAddress());
            mail.setTo(event.applicantEmail());
            mail.setSubject(email.subject());
            mail.setText(email.body());
            mailSender.send(mail);

            notification.sent(event.applicantEmail(), email.subject(), email.body(), Instant.now(clock));
            repository.save(notification);
            log.info("Emailed {} about loan {} ({})", event.applicantEmail(), event.loanId(), event.newStatus());
            return NotificationStatus.SENT;
        } catch (MailException e) {
            notification.failed(event.applicantEmail(), email.subject(), e.getMessage());
            repository.save(notification);
            throw new NotificationDeliveryException("Could not email " + event.applicantEmail(), e);
        }
    }
}
