package com.erez.loans.bridge.pubsub;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;

import com.erez.loans.bridge.auth.SalesforceSession;
import com.erez.loans.bridge.auth.SessionProvider;
import com.erez.loans.bridge.checkpoint.InMemoryReplayStore;
import com.erez.loans.bridge.kafka.EventSink;
import com.erez.loans.bridge.kafka.LoanStatusEvent;
import com.google.protobuf.ByteString;
import com.salesforce.eventbus.protobuf.ConsumerEvent;
import com.salesforce.eventbus.protobuf.FetchRequest;
import com.salesforce.eventbus.protobuf.FetchResponse;
import com.salesforce.eventbus.protobuf.ProducerEvent;
import com.salesforce.eventbus.protobuf.PubSubGrpc;
import com.salesforce.eventbus.protobuf.ReplayPreset;
import com.salesforce.eventbus.protobuf.SchemaInfo;
import com.salesforce.eventbus.protobuf.SchemaRequest;
import io.grpc.ManagedChannel;
import io.grpc.Metadata;
import io.grpc.Server;
import io.grpc.ServerCall;
import io.grpc.ServerCallHandler;
import io.grpc.ServerInterceptor;
import io.grpc.ServerInterceptors;
import io.grpc.inprocess.InProcessChannelBuilder;
import io.grpc.inprocess.InProcessServerBuilder;
import io.grpc.stub.StreamObserver;
import java.time.Duration;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * Runs the subscriber against an in-process fake of the Salesforce Pub/Sub API.
 */
class LoanEventSubscriberTest {

    private static final ByteString REPLAY_1 = ByteString.copyFromUtf8("replay-1");
    private static final String TOPIC = "/event/LoanStatusChanged__e";

    private final FakePubSub fake = new FakePubSub();
    private final List<Metadata> receivedHeaders = new CopyOnWriteArrayList<>();
    private final List<LoanStatusEvent> published = new CopyOnWriteArrayList<>();
    private final AtomicInteger sinkFailuresLeft = new AtomicInteger();

    private Server server;
    private ManagedChannel channel;
    private LoanEventSubscriber subscriber;
    private InMemoryReplayStore replayStore;

    private final SessionProvider sessions = new SessionProvider() {
        @Override
        public SalesforceSession current() {
            return new SalesforceSession("token-123", "https://example.my.salesforce.com", "00D000000000001AAA");
        }

        @Override
        public void invalidate() {
        }
    };

    private final EventSink sink = event -> {
        if (sinkFailuresLeft.getAndDecrement() > 0) {
            throw new IllegalStateException("Kafka unavailable");
        }
        published.add(event);
    };

    @BeforeEach
    void startServer() throws Exception {
        String name = InProcessServerBuilder.generateName();
        ServerInterceptor captureHeaders = new ServerInterceptor() {
            @Override
            public <Q, S> ServerCall.Listener<Q> interceptCall(ServerCall<Q, S> call, Metadata headers,
                                                               ServerCallHandler<Q, S> next) {
                receivedHeaders.add(headers);
                return next.startCall(call, headers);
            }
        };
        server = InProcessServerBuilder.forName(name).directExecutor()
                .addService(ServerInterceptors.intercept(fake, captureHeaders)).build().start();
        channel = InProcessChannelBuilder.forName(name).directExecutor().build();
        replayStore = new InMemoryReplayStore();
    }

    @AfterEach
    void stopServer() {
        if (subscriber != null) {
            subscriber.close();
        }
        channel.shutdownNow();
        server.shutdownNow();
    }

    private void startSubscriber() {
        PubSubCallCredentials credentials = new PubSubCallCredentials(sessions);
        subscriber = new LoanEventSubscriber(
                PubSubGrpc.newStub(channel).withCallCredentials(credentials),
                new SchemaCache(PubSubGrpc.newBlockingStub(channel).withCallCredentials(credentials)),
                new EventDecoder(), sink, replayStore, sessions, TOPIC, 50, Duration.ofMillis(50));
        subscriber.start();
    }

    @Test
    void forwardsEventsAndSavesTheReplayId() {
        startSubscriber();

        await().atMost(Duration.ofSeconds(5)).until(() -> published.size() == 1);
        LoanStatusEvent event = published.get(0);
        assertThat(event.loanId()).isEqualTo("a01di00001O3s0jAAB");
        assertThat(event.newStatus()).isEqualTo("Approved");
        assertThat(event.eventUuid()).isEqualTo("uuid-1");
        assertThat(replayStore.load()).contains(REPLAY_1);
    }

    @Test
    void firstSubscriptionStartsAtLatestAndSendsAuthHeaders() {
        startSubscriber();

        await().atMost(Duration.ofSeconds(5)).until(() -> !fake.requests.isEmpty());
        FetchRequest first = fake.requests.get(0);
        assertThat(first.getTopicName()).isEqualTo(TOPIC);
        assertThat(first.getReplayPreset()).isEqualTo(ReplayPreset.LATEST);
        assertThat(first.getNumRequested()).isEqualTo(50);

        Metadata headers = receivedHeaders.get(0);
        assertThat(headers.get(PubSubCallCredentials.ACCESS_TOKEN)).isEqualTo("token-123");
        assertThat(headers.get(PubSubCallCredentials.INSTANCE_URL)).isEqualTo("https://example.my.salesforce.com");
        assertThat(headers.get(PubSubCallCredentials.TENANT_ID)).isEqualTo("00D000000000001AAA");
    }

    @Test
    void resumesFromTheSavedReplayId() {
        ByteString saved = ByteString.copyFromUtf8("saved-position");
        replayStore.save(saved);

        startSubscriber();

        await().atMost(Duration.ofSeconds(5)).until(() -> !fake.requests.isEmpty());
        FetchRequest first = fake.requests.get(0);
        assertThat(first.getReplayPreset()).isEqualTo(ReplayPreset.CUSTOM);
        assertThat(first.getReplayId()).isEqualTo(saved);
    }

    @Test
    void redeliversAfterAForwardingFailure() {
        sinkFailuresLeft.set(1);

        startSubscriber();

        // First attempt fails, the stream is reopened and the same event is delivered again
        await().atMost(Duration.ofSeconds(5)).until(() -> published.size() == 1);
        assertThat(fake.subscriptions.get()).isGreaterThanOrEqualTo(2);
        assertThat(replayStore.load()).contains(REPLAY_1);
        assertThat(subscriber.forwardedCount()).isEqualTo(1);
    }

    @Test
    void stopsWhenLeadershipIsLostAndResumesFromTheCheckpointWhenRestarted() {
        startSubscriber();
        await().atMost(Duration.ofSeconds(5)).until(() -> published.size() == 1);

        subscriber.stop();
        assertThat(subscriber.isRunning()).isFalse();
        assertThat(subscriber.health().getDetails()).containsEntry("state", "standby");

        int requestsBefore = fake.requests.size();
        subscriber.start();

        await().atMost(Duration.ofSeconds(5)).until(() -> fake.requests.size() > requestsBefore);
        FetchRequest resumed = fake.requests.get(requestsBefore);
        assertThat(resumed.getReplayPreset()).isEqualTo(ReplayPreset.CUSTOM);
        assertThat(resumed.getReplayId()).isEqualTo(REPLAY_1);
    }

    /** Sends one event on every new subscription, like a replay from the subscriber's position. */
    private static final class FakePubSub extends PubSubGrpc.PubSubImplBase {

        final List<FetchRequest> requests = new CopyOnWriteArrayList<>();
        final AtomicInteger subscriptions = new AtomicInteger();

        @Override
        public void getSchema(SchemaRequest request, StreamObserver<SchemaInfo> responseObserver) {
            responseObserver.onNext(SchemaInfo.newBuilder()
                    .setSchemaId(request.getSchemaId())
                    .setSchemaJson(TestEvents.schemaJson())
                    .build());
            responseObserver.onCompleted();
        }

        @Override
        public StreamObserver<FetchRequest> subscribe(StreamObserver<FetchResponse> responses) {
            boolean[] firstRequest = {true};
            subscriptions.incrementAndGet();
            return new StreamObserver<>() {
                @Override
                public void onNext(FetchRequest request) {
                    requests.add(request);
                    if (!firstRequest[0]) {
                        return;
                    }
                    firstRequest[0] = false;
                    ProducerEvent event = ProducerEvent.newBuilder()
                            .setId("e-1")
                            .setSchemaId("schema-1")
                            .setPayload(ByteString.copyFrom(TestEvents.payload(
                                    "a01di00001O3s0jAAB", "Pending_Approval", "Approved", 30000.0,
                                    "noam@example.com", "uuid-1")))
                            .build();
                    responses.onNext(FetchResponse.newBuilder()
                            .addEvents(ConsumerEvent.newBuilder().setEvent(event).setReplayId(REPLAY_1))
                            .setLatestReplayId(REPLAY_1)
                            .setPendingNumRequested(request.getNumRequested() - 1)
                            .build());
                }

                @Override
                public void onError(Throwable t) {
                }

                @Override
                public void onCompleted() {
                    responses.onCompleted();
                }
            };
        }
    }
}
