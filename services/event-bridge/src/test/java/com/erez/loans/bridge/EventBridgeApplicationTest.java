package com.erez.loans.bridge;

import static org.assertj.core.api.Assertions.assertThat;

import com.erez.loans.bridge.kafka.EventSink;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

/** The application starts without Salesforce when the subscription is switched off. */
@SpringBootTest(properties = {
        "bridge.subscription-enabled=false",
        "spring.kafka.admin.auto-create=false",
        "spring.datasource.url=jdbc:h2:mem:bridge;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1",
        "spring.datasource.username=sa",
        "spring.datasource.password="
})
class EventBridgeApplicationTest {

    @Autowired
    private EventSink sink;

    @Test
    void contextLoads() {
        assertThat(sink).isNotNull();
    }
}