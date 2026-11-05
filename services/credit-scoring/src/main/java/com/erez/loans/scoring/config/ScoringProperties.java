package com.erez.loans.scoring.config;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;


@ConfigurationProperties("scoring")
public record ScoringProperties(String apiKey, @DefaultValue Simulation simulation) {

    public record Simulation(@DefaultValue("false") boolean enabled, @DefaultValue("15s") Duration slowDelay) {
    }
}
