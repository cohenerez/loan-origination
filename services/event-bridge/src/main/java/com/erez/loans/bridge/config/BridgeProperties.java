package com.erez.loans.bridge.config;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * @param salesforce connection to the org: OAuth client credentials and the Pub/Sub API endpoint
 * @param topic      the platform event channel to subscribe to
 * @param kafkaTopic where loan events are published
 * @param batchSize  how many events to request from Salesforce at a time (flow control)
 * @param leaderElectionEnabled  coordinate several instances through a PostgreSQL advisory lock (active/standby)
 * @param leaderLockKey          advisory lock key shared by all instances of this bridge
 * @param leaderCheckInterval    how often each instance checks or tries the lock; bounds the failover time
 */
@ConfigurationProperties("bridge")
public record BridgeProperties(
        @DefaultValue Salesforce salesforce,
        @DefaultValue("/event/LoanStatusChanged__e") String topic,
        @DefaultValue("loan-events") String kafkaTopic,
        @DefaultValue("100") int batchSize,
        @DefaultValue("true") boolean subscriptionEnabled,
        @DefaultValue("5s") Duration reconnectDelay,
        @DefaultValue("true") boolean leaderElectionEnabled,
        @DefaultValue("7270001") long leaderLockKey,
        @DefaultValue("5s") Duration leaderCheckInterval) {

    /**
     * @param loginUrl     the org's My Domain URL, e.g. https://example.my.salesforce.com (client credentials
     *                     tokens must be requested from My Domain, not login.salesforce.com)
     * @param clientId     consumer key of the External Client App
     * @param clientSecret consumer secret of the External Client App
     */
    public record Salesforce(
            String loginUrl,
            String clientId,
            String clientSecret,
            @DefaultValue("api.pubsub.salesforce.com") String pubsubHost,
            @DefaultValue("7443") int pubsubPort) {
    }
}
