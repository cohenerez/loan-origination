package com.erez.loans.notifications.config;

import java.time.Clock;
import java.util.LinkedHashMap;
import java.util.Map;
import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.common.serialization.ByteArraySerializer;
import org.apache.kafka.common.serialization.Serializer;
import org.apache.kafka.common.serialization.StringSerializer;
import org.springframework.boot.autoconfigure.kafka.KafkaProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.config.TopicBuilder;
import org.springframework.kafka.core.DefaultKafkaProducerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.listener.DeadLetterPublishingRecoverer;
import org.springframework.kafka.listener.DefaultErrorHandler;
import org.springframework.kafka.support.serializer.DelegatingByTypeSerializer;
import org.springframework.kafka.support.serializer.JsonSerializer;
import org.springframework.util.backoff.FixedBackOff;
import org.apache.kafka.common.TopicPartition;

@Configuration
public class KafkaConfiguration {


    @Bean
    public DefaultErrorHandler kafkaErrorHandler(KafkaProperties kafkaProperties,
                                                 NotificationProperties properties) {
        String deadLetterTopic = properties.topic() + ".DLT";
        DeadLetterPublishingRecoverer recoverer = new DeadLetterPublishingRecoverer( deadLetterTemplate(kafkaProperties),

                     (record, ex) -> new TopicPartition(deadLetterTopic, record.partition()));
        return new DefaultErrorHandler(recoverer, new FixedBackOff(2000L, 3L));
    }

    @Bean
    public NewTopic deadLetterTopic(NotificationProperties properties) {
          return TopicBuilder.name(properties.topic() + ".DLT").partitions(3).replicas(1).build();
    }

    @Bean
    public Clock clock() {
        return Clock.systemUTC();
    }


    private static KafkaTemplate<Object, Object> deadLetterTemplate(KafkaProperties kafkaProperties) {
        Map<String, Object> config = kafkaProperties.buildProducerProperties(null);
        return new KafkaTemplate<>(new DefaultKafkaProducerFactory<>(
                config, byTypeSerializer(), byTypeSerializer()));
    }

    private static Serializer<Object> byTypeSerializer() {
        Map<Class<?>, Serializer<?>> delegates = new LinkedHashMap<>();
        delegates.put(byte[].class, new ByteArraySerializer());
        delegates.put(String.class, new StringSerializer());
        delegates.put(Object.class, new JsonSerializer<>());
        return new DelegatingByTypeSerializer(delegates, true);
    }
}