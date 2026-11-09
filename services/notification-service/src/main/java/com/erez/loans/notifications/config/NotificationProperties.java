package com.erez.loans.notifications.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;


@ConfigurationProperties("notifications")
public record NotificationProperties(
        @DefaultValue("loan-events") String topic,
        @DefaultValue("loans@erez-bank.example") String fromAddress,
        @DefaultValue("Erez Bank") String bankName) {
}
