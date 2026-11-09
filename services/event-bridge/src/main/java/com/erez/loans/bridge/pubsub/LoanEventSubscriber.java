package com.erez.loans.bridge.pubsub;

import com.erez.loans.bridge.auth.SessionProvider;
import com.erez.loans.bridge.checkpoint.ReplayStore;
import com.erez.loans.bridge.kafka.EventSink;
import com.erez.loans.bridge.kafka.LoanStatusEvent;
import com.google.protobuf.ByteString;
import com.salesforce.eventbus.protobuf.ConsumerEvent;
import com.salesforce.eventbus.protobuf.FetchRequest;
import com.salesforce.eventbus.protobuf.FetchResponse;
import com.salesforce.eventbus.protobuf.PubSubGrpc;
import com.salesforce.eventbus.protobuf.ReplayPreset;
import io.grpc.Status;
import io.grpc.stub.StreamObserver;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.Optional;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import org.apache.avro.Schema;
import org.apache.avro.generic.GenericRecord;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.actuate.health.Health;
import org.springframework.boot.actuate.health.HealthIndicator;

/**
 * Long-lived Pub/Sub API subscription to LoanStatusChanged__e.
 *
 * <ul>
 *   <li>Resumes from the last saved replay ID (CUSTOM) or starts at LATEST the first time.</li>
 *   <li>Flow control: asks for {@code batchSize} events and asks again when Salesforce has none left
 *       pending.</li>
 *   <li>At-least-once: the replay ID is saved only after Kafka acknowledged the event. If forwarding
 *       fails, the stream is cancelled and reopened from the last saved replay ID, so the event is
 *       delivered again. Consumers drop duplicates by event UUID.</li>
 *   <li>Reconnects after any stream error, and logs in again when the token was rejected.</li>
 * </ul>
 *
 * <p>Started and stopped by {@code LeaderElection}: only the instance holding the leader lock subscribes.
 */
public class LoanEventSubscriber implements HealthIndicator, AutoCloseable {

    private static final Logger log = LoggerFactory.getLogger(LoanEventSubscriber.class);

    private final PubSubGrpc.PubSubStub stub;
    private final SchemaCache schemas;
    private final EventDecoder decoder;
    private final EventSink sink;
    private final ReplayStore replayStore;
    private final SessionProvider sessions;
    private final String topic;
    private final int batchSize;
    private final Duration reconnectDelay;

    private final ScheduledExecutorService scheduler = Executors.newSingleThreadScheduledExecutor(runnable -> {
        Thread thread = new Thread(runnable, "pubsub-reconnect");
        thread.setDaemon(true);
        return thread;
    });
    private final AtomicBoolean reconnectPending = new AtomicBoolean();
    private final AtomicLong forwarded = new AtomicLong();
    private final AtomicLong generation = new AtomicLong();

    private volatile boolean running;
    private volatile boolean subscribed;
    private volatile StreamObserver<FetchRequest> requests;
    private volatile Instant lastEventAt;
    private volatile String lastError;

    public LoanEventSubscriber(PubSubGrpc.PubSubStub stub, SchemaCache schemas, EventDecoder decoder,
                               EventSink sink, ReplayStore replayStore, SessionProvider sessions,
                               String topic, int batchSize, Duration reconnectDelay) {
        this.stub = stub;
        this.schemas = schemas;
        this.decoder = decoder;
        this.sink = sink;
        this.replayStore = replayStore;
        this.sessions = sessions;
        this.topic = topic;
        this.batchSize = batchSize;
        this.reconnectDelay = reconnectDelay;
    }

    // ---------- lifecycle ----------

    /** Opens the subscription (called when this instance becomes leader). */
    public synchronized void start() {
        if (running) {
            return;
        }
        running = true;
        subscribe();
    }

    /** Closes the subscription (called when this instance loses leadership); can be started again. */
    public synchronized void stop() {
        if (!running) {
            return;
        }
        running = false;
        subscribed = false;
        if (requests != null) {
            requests.onCompleted();
            requests = null;
        }
        generation.incrementAndGet();
        log.info("Subscription stopped");
    }

    public boolean isRunning() {
        return running;
    }

    /** Final shutdown when the application stops. */
    @Override
    public void close() {
        stop();
        scheduler.shutdownNow();
    }

    public long forwardedCount() {
        return forwarded.get();
    }

    // ---------- subscription ----------

    synchronized void subscribe() {
        if (!running) {
            return;
        }
        requests = stub.subscribe(new ResponseObserver(generation.incrementAndGet()));
        FetchRequest.Builder first = FetchRequest.newBuilder().setTopicName(topic).setNumRequested(batchSize);
        Optional<ByteString> replayId = replayStore.load();
        if (replayId.isPresent()) {
            first.setReplayPreset(ReplayPreset.CUSTOM).setReplayId(replayId.get());
        } else {
            first.setReplayPreset(ReplayPreset.LATEST);
        }
        requests.onNext(first.build());
        subscribed = true;
        log.info("Subscribed to {} from {}", topic, replayId.isPresent() ? "the saved replay ID" : "LATEST");
    }

    private synchronized void requestMore() {
        if (requests != null) {
            requests.onNext(FetchRequest.newBuilder().setTopicName(topic).setNumRequested(batchSize).build());
        }
    }

    private void scheduleReconnect() {
        subscribed = false;
        if (running && reconnectPending.compareAndSet(false, true)) {
            scheduler.schedule(() -> {
                reconnectPending.set(false);
                try {
                    subscribe();
                } catch (RuntimeException e) {
                    lastError = e.getMessage();
                    log.warn("Resubscribe failed: {}", e.getMessage());
                    scheduleReconnect();
                }
            }, reconnectDelay.toMillis(), TimeUnit.MILLISECONDS);
        }
    }

    /** Forwards one event; returns false if it could not be forwarded. */
    private boolean forward(ConsumerEvent consumerEvent) {
        try {
            Schema schema = schemas.get(consumerEvent.getEvent().getSchemaId());
            GenericRecord record = decoder.decode(consumerEvent.getEvent().getPayload().toByteArray(), schema);
            String replayId = Base64.getEncoder().encodeToString(consumerEvent.getReplayId().toByteArray());
            LoanStatusEvent event = decoder.toLoanEvent(record, replayId);

            sink.publish(event);
            replayStore.save(consumerEvent.getReplayId());

            forwarded.incrementAndGet();
            lastEventAt = Instant.now();
            log.info("Forwarded loan {} {} -> {} (event {})",
                    event.loanId(), event.oldStatus(), event.newStatus(), event.eventUuid());
            return true;
        } catch (Exception e) {
            lastError = e.getMessage();
            log.error("Could not forward event; will resume from the last saved replay ID", e);
            return false;
        }
    }

    private final class ResponseObserver implements StreamObserver<FetchResponse> {

        /** Callbacks from a stream that has since been replaced are ignored. */
        private final long streamGeneration;

        ResponseObserver(long streamGeneration) {
            this.streamGeneration = streamGeneration;
        }

        private boolean stale() {
            return streamGeneration != generation.get();
        }

        @Override
        public void onNext(FetchResponse response) {
            if (stale()) {
                return;
            }
            lastError = null;
            for (ConsumerEvent event : response.getEventsList()) {
                if (!forward(event)) {
                    // Cancel the stream; onError reconnects from the last saved replay ID
                    synchronized (LoanEventSubscriber.this) {
                        if (requests != null) {
                            requests.onError(Status.UNAVAILABLE.withDescription("Forwarding failed").asRuntimeException());
                        }
                    }
                    return;
                }
            }
            if (response.getEventsCount() == 0 && !response.getLatestReplayId().isEmpty()) {
                // Keepalive: nothing new, but the position moved on
                replayStore.save(response.getLatestReplayId());
            }
            if (response.getPendingNumRequested() == 0) {
                requestMore();
            }
        }

        @Override
        public void onError(Throwable t) {
            if (stale()) {
                return;
            }
            Status status = Status.fromThrowable(t);
            lastError = status.getCode() + (status.getDescription() == null ? "" : ": " + status.getDescription());
            if (status.getCode() == Status.Code.UNAUTHENTICATED) {
                sessions.invalidate();
            }
            if (running) {
                log.warn("Subscription ended ({}); reconnecting in {} ms", lastError, reconnectDelay.toMillis());
            }
            scheduleReconnect();
        }

        @Override
        public void onCompleted() {
            if (stale()) {
                return;
            }
            log.info("Salesforce closed the subscription; reconnecting");
            scheduleReconnect();
        }
    }

    // ---------- health ----------

    @Override
    public Health health() {
        Health.Builder builder;
        if (!running) {
            builder = Health.up().withDetail("state", "standby");
        } else {
            builder = subscribed ? Health.up().withDetail("state", "subscribed") : Health.down();
        }
        builder.withDetail("topic", topic).withDetail("forwarded", forwarded.get());
        if (lastEventAt != null) {
            builder.withDetail("lastEventAt", lastEventAt.toString());
        }
        if (lastError != null) {
            builder.withDetail("lastError", lastError);
        }
        return builder.build();
    }
}
