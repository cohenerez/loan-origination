package com.erez.loans.bridge.leader;

/** For a single instance without coordination (bridge.leader-election-enabled=false). */
public class AlwaysLeaderLock implements LeaderLock {

    @Override
    public boolean tryAcquire() {
        return true;
    }

    @Override
    public boolean isHeld() {
        return true;
    }

    @Override
    public void release() {
        // nothing to release
    }
}
