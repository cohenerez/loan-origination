package com.erez.loans.bridge.leader;

import java.time.Duration;
import java.time.Instant;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.actuate.health.Health;
import org.springframework.boot.actuate.health.HealthIndicator;
import org.springframework.context.SmartLifecycle;

/**
 * Active/standby coordination. Every instance checks the lock every {@code checkInterval}:
 * a standby tries to take it, the leader checks it still holds it. Taking the lock starts the
 * subscription; losing it stops the subscription immediately.
 *
 * <p>Failover time is roughly the check interval plus the time PostgreSQL needs to notice the old
 * session is gone. During that window both instances may briefly forward the same events; that is
 * safe because consumers drop duplicates by event UUID and the checkpoint only moves forward from
 * Salesforce's replay order.
 */
public class LeaderElection implements SmartLifecycle, HealthIndicator {

    /** What happens when this instance gains or loses leadership. */
    public interface Listener {
        void onElected();

        void onRevoked();
    }

    private static final Logger log = LoggerFactory.getLogger(LeaderElection.class);

    private final LeaderLock lock;
    private final Listener listener;
    private final Duration checkInterval;

    private ScheduledExecutorService scheduler;
    private volatile boolean running;
    private volatile boolean leader;
    private volatile Instant leaderSince;

    public LeaderElection(LeaderLock lock, Listener listener, Duration checkInterval) {
        this.lock = lock;
        this.listener = listener;
        this.checkInterval = checkInterval;
    }

    @Override
    public synchronized void start() {
        running = true;
        scheduler = Executors.newSingleThreadScheduledExecutor(runnable -> {
            Thread thread = new Thread(runnable, "leader-election");
            thread.setDaemon(true);
            return thread;
        });
        scheduler.scheduleWithFixedDelay(this::tick, 0, checkInterval.toMillis(), TimeUnit.MILLISECONDS);
    }

    @Override
    public synchronized void stop() {
        running = false;
        if (scheduler != null) {
            scheduler.shutdownNow();
        }
        if (leader) {
            leader = false;
            listener.onRevoked();
        }
        lock.release();
    }

    @Override
    public boolean isRunning() {
        return running;
    }

    public boolean isLeader() {
        return leader;
    }

    /** One election round. Package-private so tests can drive it without timing. */
    synchronized void tick() {
        try {
            if (leader) {
                if (!lock.isHeld()) {
                    leader = false;
                    leaderSince = null;
                    log.warn("Lost the leader lock; stopping the subscription");
                    listener.onRevoked();
                }
                return;
            }
            if (lock.tryAcquire()) {
                leader = true;
                leaderSince = Instant.now();
                log.info("Elected leader; starting the subscription");
                listener.onElected();
            }
        } catch (RuntimeException e) {
            log.warn("Leader election round failed: {}", e.getMessage());
        }
    }

    @Override
    public Health health() {
        // A standby is healthy too: it is ready to take over
        Health.Builder builder = Health.up().withDetail("role", leader ? "leader" : "standby");
        if (leaderSince != null) {
            builder.withDetail("leaderSince", leaderSince.toString());
        }
        return builder.build();
    }
}
