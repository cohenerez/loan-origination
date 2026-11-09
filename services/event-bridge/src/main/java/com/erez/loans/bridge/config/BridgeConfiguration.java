package com.erez.loans.bridge.config;

import com.erez.loans.bridge.auth.SessionProvider;
import com.erez.loans.bridge.checkpoint.JdbcReplayStore;
import com.erez.loans.bridge.checkpoint.ReplayStore;
import com.erez.loans.bridge.kafka.EventSink;
import com.erez.loans.bridge.leader.AlwaysLeaderLock;
import com.erez.loans.bridge.leader.LeaderElection;
import com.erez.loans.bridge.leader.LeaderLock;
import com.erez.loans.bridge.leader.PostgresAdvisoryLock;
import com.erez.loans.bridge.pubsub.EventDecoder;
import com.erez.loans.bridge.pubsub.LoanEventSubscriber;
import com.erez.loans.bridge.pubsub.PubSubCallCredentials;
import com.erez.loans.bridge.pubsub.SchemaCache;
import com.salesforce.eventbus.protobuf.PubSubGrpc;
import io.grpc.ManagedChannel;
import io.grpc.ManagedChannelBuilder;
import java.util.concurrent.TimeUnit;
import javax.sql.DataSource;
import org.apache.kafka.clients.admin.NewTopic;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.kafka.config.TopicBuilder;

@Configuration
public class BridgeConfiguration {

    @Bean
    public NewTopic loanEventsTopic(BridgeProperties properties) {
        // Keyed by loan ID: 3 partitions allow parallel consumers while keeping each loan's events in order
        return TopicBuilder.name(properties.kafkaTopic()).partitions(3).replicas(1).build();
    }

    @Bean
    public ReplayStore replayStore(JdbcTemplate jdbcTemplate, BridgeProperties properties) {
        return new JdbcReplayStore(jdbcTemplate, properties.topic());
    }

    @Bean
    public EventDecoder eventDecoder() {
        return new EventDecoder();
    }

    @Bean // ManagedChannel.shutdown() is called on close
    @ConditionalOnProperty(name = "bridge.subscription-enabled", havingValue = "true", matchIfMissing = true)
    public ManagedChannel pubSubChannel(BridgeProperties properties) {
        return ManagedChannelBuilder
                .forAddress(properties.salesforce().pubsubHost(), properties.salesforce().pubsubPort())
                .useTransportSecurity()
                .keepAliveTime(60, TimeUnit.SECONDS)
                .build();
    }

    @Bean // close() is called on shutdown
    @ConditionalOnProperty(name = "bridge.subscription-enabled", havingValue = "true", matchIfMissing = true)
    public LoanEventSubscriber loanEventSubscriber(ManagedChannel channel, SessionProvider sessions, EventDecoder decoder,
                                                   EventSink sink, ReplayStore replayStore, BridgeProperties properties) {
        PubSubCallCredentials credentials = new PubSubCallCredentials(sessions);
        SchemaCache schemas = new SchemaCache(PubSubGrpc.newBlockingStub(channel).withCallCredentials(credentials));
        return new LoanEventSubscriber(
                PubSubGrpc.newStub(channel).withCallCredentials(credentials),
                schemas, decoder, sink, replayStore, sessions,
                properties.topic(), properties.batchSize(), properties.reconnectDelay());
    }

    @Bean
    @ConditionalOnProperty(name = "bridge.subscription-enabled", havingValue = "true", matchIfMissing = true)
    public LeaderLock leaderLock(DataSource dataSource, BridgeProperties properties) {
        return properties.leaderElectionEnabled()
                ? new PostgresAdvisoryLock(dataSource, properties.leaderLockKey())
                : new AlwaysLeaderLock();
    }

    /** Only the instance holding the lock subscribes; the others wait as standby. */
    @Bean
    @ConditionalOnProperty(name = "bridge.subscription-enabled", havingValue = "true", matchIfMissing = true)
    public LeaderElection leaderElection(LeaderLock lock, LoanEventSubscriber subscriber, BridgeProperties properties) {
        return new LeaderElection(lock, new LeaderElection.Listener() {
            @Override
            public void onElected() {
                subscriber.start();
            }

            @Override
            public void onRevoked() {
                subscriber.stop();
            }
        }, properties.leaderCheckInterval());
    }
}
