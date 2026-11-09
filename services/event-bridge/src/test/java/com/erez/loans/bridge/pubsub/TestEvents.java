package com.erez.loans.bridge.pubsub;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import org.apache.avro.Schema;
import org.apache.avro.generic.GenericData;
import org.apache.avro.generic.GenericDatumWriter;
import org.apache.avro.generic.GenericRecord;
import org.apache.avro.io.BinaryEncoder;
import org.apache.avro.io.EncoderFactory;

/** Builds Avro payloads shaped like the ones Salesforce sends for LoanStatusChanged__e. */
final class TestEvents {

    static final long CREATED_DATE = 1_793_950_000_000L;

    private TestEvents() {
    }

    static String schemaJson() {
        try (InputStream in = TestEvents.class.getResourceAsStream("/loan-status-changed.avsc")) {
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    static Schema schema() {
        return new Schema.Parser().parse(schemaJson());
    }

    static byte[] payload(String loanId, String oldStatus, String newStatus, Double amount, String email, String uuid) {
        Schema schema = schema();
        GenericRecord record = new GenericData.Record(schema);
        record.put("CreatedDate", CREATED_DATE);
        record.put("CreatedById", "005000000000001AAA");
        record.put("Loan_Id__c", loanId);
        record.put("Old_Status__c", oldStatus);
        record.put("New_Status__c", newStatus);
        record.put("Amount__c", amount);
        record.put("Applicant_Email__c", email);
        record.put("Event_Uuid__c", uuid);
        try {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            BinaryEncoder encoder = EncoderFactory.get().binaryEncoder(out, null);
            new GenericDatumWriter<GenericRecord>(schema).write(record, encoder);
            encoder.flush();
            return out.toByteArray();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
