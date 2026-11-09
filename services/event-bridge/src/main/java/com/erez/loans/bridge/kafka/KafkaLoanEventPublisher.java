package com.erez.loans.bridge.kafka;

import com.erez.loans.bridge.config.BridgeProperties;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

/**
 * Publishes loan events to Kafka, keyed by loan ID so all changes to one loan stay in order on one
 * partition. Waits for the broker's acknowledgement before returning, so the replay ID is only
 * saved for events Kafka has actually stored.
 */
@Component
public class KafkaLoanEventPublisher implements EventSink {

    static final String EVENT_UUID_HEADER = "event-uuid";
    private static final long SEND_TIMEOUT_SECONDS = 10;

    private final KafkaTemplate<String, LoanStatusEvent> kafkaTemplate;
    private final String topic;

    public KafkaLoanEventPublisher(KafkaTemplate<String, LoanStatusEvent> kafkaTemplate, BridgeProperties properties) {
        this.kafkaTemplate = kafkaTemplate;
        this.topic = properties.kafkaTopic();
    }

    @Override
    public void publish(LoanStatusEvent event) throws Exception {
        ProducerRecord<String, LoanStatusEvent> record = new ProducerRecord<>(topic, event.loanId(), event);
        if (event.eventUuid() != null) {
            record.headers().add(EVENT_UUID_HEADER, event.eventUuid().getBytes(StandardCharsets.UTF_8));
        }
        kafkaTemplate.send(record).get(SEND_TIMEOUT_SECONDS, TimeUnit.SECONDS);
    }
}
