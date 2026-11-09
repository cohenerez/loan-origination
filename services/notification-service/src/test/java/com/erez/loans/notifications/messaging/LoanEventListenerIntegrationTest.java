package com.erez.loans.notifications.messaging;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;

import com.erez.loans.notifications.domain.NotificationRepository;
import com.erez.loans.notifications.domain.NotificationStatus;
import java.time.Duration;
import java.util.Map;

import org.apache.kafka.clients.admin.AdminClient;
import org.apache.kafka.clients.admin.AdminClientConfig;
import org.apache.kafka.clients.consumer.Consumer;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.apache.kafka.common.serialization.StringSerializer;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.kafka.core.DefaultKafkaConsumerFactory;
import org.springframework.kafka.core.DefaultKafkaProducerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.test.EmbeddedKafkaBroker;
import org.springframework.kafka.test.context.EmbeddedKafka;
import org.springframework.kafka.test.utils.KafkaTestUtils;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import java.util.List;
import java.util.stream.IntStream;
import org.apache.kafka.common.TopicPartition;


@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:notifications-it;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1",
        "spring.datasource.username=sa",
        "spring.datasource.password=",
        "spring.kafka.consumer.auto-offset-reset=earliest",
        // fail fast in tests: a stuck send becomes an error within a few seconds instead of minutes
        "spring.kafka.producer.properties.max.block.ms=5000",
        "spring.kafka.producer.properties.request.timeout.ms=5000",
        "spring.kafka.producer.properties.delivery.timeout.ms=8000",
        "logging.level.org.springframework.kafka.listener=DEBUG"
})
@EmbeddedKafka(partitions = 3, topics = {"loan-events", "loan-events.DLT"},
        bootstrapServersProperty = "spring.kafka.bootstrap-servers")
class LoanEventListenerIntegrationTest {

    @Autowired
    private EmbeddedKafkaBroker broker;

    @Autowired
    private NotificationRepository repository;

    @MockitoBean
    private JavaMailSender mailSender;

    private KafkaTemplate<String, String> rawProducer() {
        Map<String, Object> props = KafkaTestUtils.producerProps(broker);
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
        return new KafkaTemplate<>(new DefaultKafkaProducerFactory<>(props));
    }

    @Test
    void emailsTheApplicantForAnEventOnTheTopic() {
        String json = """
                {"eventUuid":"it-uuid-1","loanId":"a01di00001O3s0jAAB","oldStatus":"Pending_Approval",
                 "newStatus":"Approved","amount":30000,"applicantEmail":"noam@example.com",
                 "occurredAt":"2026-11-06T10:00:00Z","replayId":"cmVwbGF5","someFutureField":true}
                """;

        rawProducer().send("loan-events", "a01di00001O3s0jAAB", json);

        await().atMost(Duration.ofSeconds(20)).untilAsserted(() ->
                assertThat(repository.findByEventUuid("it-uuid-1"))
                        .hasValueSatisfying(n -> assertThat(n.getStatus()).isEqualTo(NotificationStatus.SENT)));
        verify(mailSender).send(any(SimpleMailMessage.class));
    }

    @Test
    void malformedMessagesGoToTheDeadLetterTopic() throws Exception {
        rawProducer().send("loan-events", "bad-key", "this is not json").get();

        Map<String, Object> props = KafkaTestUtils.consumerProps("dlt-check", "false", broker);
        try (Consumer<String, String> consumer = new DefaultKafkaConsumerFactory<>(
                props, new StringDeserializer(), new StringDeserializer()).createConsumer()) {
            List<TopicPartition> partitions = IntStream.range(0, 3)
                    .mapToObj(p -> new TopicPartition("loan-events.DLT", p))
                    .toList();
            consumer.assign(partitions);
            consumer.seekToBeginning(partitions);

            try {
                ConsumerRecord<String, String> record =
                        KafkaTestUtils.getSingleRecord(consumer, "loan-events.DLT", Duration.ofSeconds(20));
                assertThat(record.key()).isEqualTo("bad-key");
                assertThat(record.value()).isEqualTo("this is not json");
            } finally {
                // DIAG: where did the message actually go?
                List<TopicPartition> source = IntStream.range(0, 3)
                        .mapToObj(p -> new TopicPartition("loan-events", p)).toList();
                System.out.println("DIAG brokers   = " + broker.getBrokersAsString());
                System.out.println("DIAG source    = " + consumer.endOffsets(source));
                System.out.println("DIAG DLT       = " + consumer.endOffsets(partitions));

                try (AdminClient admin = AdminClient.create(Map.of(
                        AdminClientConfig.BOOTSTRAP_SERVERS_CONFIG, broker.getBrokersAsString()))) {
                    System.out.println("DIAG topics    = " + admin.listTopics().names().get());
                    System.out.println("DIAG DLT desc  = "
                            + admin.describeTopics(List.of("loan-events.DLT")).allTopicNames().get());
                }
            }
        }
    }
}
