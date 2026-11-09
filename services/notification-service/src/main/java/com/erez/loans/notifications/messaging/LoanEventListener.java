package com.erez.loans.notifications.messaging;

import com.erez.loans.notifications.domain.NotificationService;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

@Component
public class LoanEventListener {

    private final NotificationService service;

    public LoanEventListener(NotificationService service) {
        this.service = service;
    }

    @KafkaListener(topics = "${notifications.topic}", groupId = "notification-service")
    public void onLoanEvent(LoanStatusEvent event) {
        service.handle(event);
    }
}
