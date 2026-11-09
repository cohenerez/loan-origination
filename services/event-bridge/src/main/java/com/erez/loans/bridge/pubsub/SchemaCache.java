package com.erez.loans.bridge.pubsub;

import com.salesforce.eventbus.protobuf.PubSubGrpc;
import com.salesforce.eventbus.protobuf.SchemaRequest;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.apache.avro.Schema;

/**
 * Fetches Avro schemas by ID from the Pub/Sub API and keeps them. A schema ID changes only when the
 * event's fields change, so after the first event this costs nothing.
 */
public class SchemaCache {

    private final PubSubGrpc.PubSubBlockingStub stub;
    private final Map<String, Schema> schemas = new ConcurrentHashMap<>();

    public SchemaCache(PubSubGrpc.PubSubBlockingStub stub) {
        this.stub = stub;
    }

    public Schema get(String schemaId) {
        return schemas.computeIfAbsent(schemaId, id -> {
            String json = stub.getSchema(SchemaRequest.newBuilder().setSchemaId(id).build()).getSchemaJson();
            return new Schema.Parser().parse(json);
        });
    }
}
