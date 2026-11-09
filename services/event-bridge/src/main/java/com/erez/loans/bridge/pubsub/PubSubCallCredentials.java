package com.erez.loans.bridge.pubsub;

import com.erez.loans.bridge.auth.SalesforceSession;
import com.erez.loans.bridge.auth.SessionProvider;
import io.grpc.CallCredentials;
import io.grpc.Metadata;
import io.grpc.Status;
import java.util.concurrent.Executor;

/** Adds the three headers the Pub/Sub API authenticates with to every gRPC call. */
public class PubSubCallCredentials extends CallCredentials {

    static final Metadata.Key<String> ACCESS_TOKEN = Metadata.Key.of("accesstoken", Metadata.ASCII_STRING_MARSHALLER);
    static final Metadata.Key<String> INSTANCE_URL = Metadata.Key.of("instanceurl", Metadata.ASCII_STRING_MARSHALLER);
    static final Metadata.Key<String> TENANT_ID = Metadata.Key.of("tenantid", Metadata.ASCII_STRING_MARSHALLER);

    private final SessionProvider sessions;

    public PubSubCallCredentials(SessionProvider sessions) {
        this.sessions = sessions;
    }

    @Override
    public void applyRequestMetadata(RequestInfo requestInfo, Executor appExecutor, MetadataApplier applier) {
        appExecutor.execute(() -> {
            try {
                SalesforceSession session = sessions.current();
                Metadata headers = new Metadata();
                headers.put(ACCESS_TOKEN, session.accessToken());
                headers.put(INSTANCE_URL, session.instanceUrl());
                headers.put(TENANT_ID, session.tenantId());
                applier.apply(headers);
            } catch (RuntimeException e) {
                applier.fail(Status.UNAUTHENTICATED.withDescription("Salesforce login failed: " + e.getMessage()).withCause(e));
            }
        });
    }
}
