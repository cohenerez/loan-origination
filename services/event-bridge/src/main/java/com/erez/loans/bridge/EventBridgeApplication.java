package com.erez.loans.bridge;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

@SpringBootApplication
@ConfigurationPropertiesScan
public class EventBridgeApplication {

    public static void main(String[] args) {

        SpringApplication.run(EventBridgeApplication.class, args);
    }
}
