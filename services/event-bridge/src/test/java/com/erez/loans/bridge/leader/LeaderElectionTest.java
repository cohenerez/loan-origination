package com.erez.loans.bridge.leader;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class LeaderElectionTest {

    /** A lock another instance may be holding, and whose session can drop. */
    private static final class FakeLock implements LeaderLock {
        boolean heldElsewhere;
        boolean held;
        boolean released;

        @Override
        public boolean tryAcquire() {
            if (!heldElsewhere) {
                held = true;
            }
            return held;
        }

        @Override
        public boolean isHeld() {
            return held;
        }

        @Override
        public void release() {
            held = false;
            released = true;
        }
    }

    private final FakeLock lock = new FakeLock();
    private final List<String> calls = new ArrayList<>();
    private final LeaderElection election = new LeaderElection(lock, new LeaderElection.Listener() {
        @Override
        public void onElected() {
            calls.add("elected");
        }

        @Override
        public void onRevoked() {
            calls.add("revoked");
        }
    }, Duration.ofSeconds(5));

    @Test
    void staysStandbyWhileAnotherInstanceHoldsTheLock() {
        lock.heldElsewhere = true;

        election.tick();
        election.tick();

        assertThat(election.isLeader()).isFalse();
        assertThat(calls).isEmpty();
        assertThat(election.health().getDetails()).containsEntry("role", "standby");
    }

    @Test
    void takesOverWhenTheLockBecomesFree() {
        lock.heldElsewhere = true;
        election.tick();

        lock.heldElsewhere = false;
        election.tick();
        election.tick();

        assertThat(election.isLeader()).isTrue();
        assertThat(calls).containsExactly("elected");
        assertThat(election.health().getDetails()).containsEntry("role", "leader");
    }

    @Test
    void stopsSubscribingWhenTheLockIsLostAndCanBeElectedAgain() {
        election.tick();
        lock.held = false;          // database session dropped
        lock.heldElsewhere = true;  // and another instance took over
        election.tick();

        assertThat(election.isLeader()).isFalse();
        assertThat(calls).containsExactly("elected", "revoked");

        lock.heldElsewhere = false; // the other instance went away
        election.tick();
        assertThat(calls).containsExactly("elected", "revoked", "elected");
    }

    @Test
    void stopReleasesTheLockAndStopsTheSubscription() {
        election.tick();

        election.stop();

        assertThat(lock.released).isTrue();
        assertThat(calls).containsExactly("elected", "revoked");
    }

    @Test
    void alwaysLeaderLockElectsImmediately() {
        LeaderElection single = new LeaderElection(new AlwaysLeaderLock(), new LeaderElection.Listener() {
            @Override
            public void onElected() {
                calls.add("elected");
            }

            @Override
            public void onRevoked() {
                calls.add("revoked");
            }
        }, Duration.ofSeconds(5));

        single.tick();

        assertThat(single.isLeader()).isTrue();
    }
}
