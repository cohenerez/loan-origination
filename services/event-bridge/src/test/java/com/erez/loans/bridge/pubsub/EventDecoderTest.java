package com.erez.loans.bridge.pubsub;

import static org.assertj.core.api.Assertions.assertThat;

import com.erez.loans.bridge.kafka.LoanStatusEvent;
import java.time.Instant;
import org.apache.avro.generic.GenericRecord;
import org.junit.jupiter.api.Test;

class EventDecoderTest {

    private final EventDecoder decoder = new EventDecoder();

    @Test
    void decodesAndMapsAllFields() throws Exception {
        byte[] payload = TestEvents.payload("a01di00001O3s0jAAB", "Scoring", "Pending_Approval",
                150000.0, "dana.levi@example.com", "6f1c2e7a-0b7e-4c1d-9a51-3f0a8c2d1e44");

        GenericRecord record = decoder.decode(payload, TestEvents.schema());
        LoanStatusEvent event = decoder.toLoanEvent(record, "cmVwbGF5");

        assertThat(event.loanId()).isEqualTo("a01di00001O3s0jAAB");
        assertThat(event.oldStatus()).isEqualTo("Scoring");
        assertThat(event.newStatus()).isEqualTo("Pending_Approval");
        assertThat(event.amount()).isEqualByComparingTo("150000");
        assertThat(event.applicantEmail()).isEqualTo("dana.levi@example.com");
        assertThat(event.eventUuid()).isEqualTo("6f1c2e7a-0b7e-4c1d-9a51-3f0a8c2d1e44");
        assertThat(event.occurredAt()).isEqualTo(Instant.ofEpochMilli(TestEvents.CREATED_DATE).toString());
        assertThat(event.replayId()).isEqualTo("cmVwbGF5");
    }

    @Test
    void nullFieldsStayNull() throws Exception {
        byte[] payload = TestEvents.payload("a01", null, "Draft", null, null, "u-1");

        LoanStatusEvent event = decoder.toLoanEvent(decoder.decode(payload, TestEvents.schema()), "r");

        assertThat(event.oldStatus()).isNull();
        assertThat(event.amount()).isNull();
        assertThat(event.applicantEmail()).isNull();
    }
}
