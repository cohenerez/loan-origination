package com.erez.loans.bridge.pubsub;

import com.erez.loans.bridge.kafka.LoanStatusEvent;
import java.io.IOException;
import java.math.BigDecimal;
import java.time.Instant;
import org.apache.avro.Schema;
import org.apache.avro.generic.GenericDatumReader;
import org.apache.avro.generic.GenericRecord;
import org.apache.avro.io.BinaryDecoder;
import org.apache.avro.io.DatumReader;
import org.apache.avro.io.DecoderFactory;

/** Decodes Avro event payloads and maps LoanStatusChanged__e fields to {@link LoanStatusEvent}. */
public class EventDecoder {

    public GenericRecord decode(byte[] payload, Schema schema) throws IOException {
        DatumReader<GenericRecord> reader = new GenericDatumReader<>(schema);
        BinaryDecoder decoder = DecoderFactory.get().binaryDecoder(payload, null);
        return reader.read(null, decoder);
    }

    public LoanStatusEvent toLoanEvent(GenericRecord record, String replayId) {
        return new LoanStatusEvent(
                text(record, "Event_Uuid__c"),
                text(record, "Loan_Id__c"),
                text(record, "Old_Status__c"),
                text(record, "New_Status__c"),
                decimal(record, "Amount__c"),
                text(record, "Applicant_Email__c"),
                createdDate(record),
                replayId);
    }

    static String text(GenericRecord record, String field) {
        Object value = valueOf(record, field);
        return value == null ? null : value.toString();
    }

    static BigDecimal decimal(GenericRecord record, String field) {
        Object value = valueOf(record, field);
        if (value instanceof Number number) {
            return new BigDecimal(number.toString());
        }
        return value == null ? null : new BigDecimal(value.toString());
    }

    private static String createdDate(GenericRecord record) {
        Object value = valueOf(record, "CreatedDate");
        return value instanceof Long millis ? Instant.ofEpochMilli(millis).toString() : null;
    }

    private static Object valueOf(GenericRecord record, String field) {
        return record.getSchema().getField(field) == null ? null : record.get(field);
    }
}
