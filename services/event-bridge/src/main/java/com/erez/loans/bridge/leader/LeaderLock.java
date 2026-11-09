package com.erez.loans.bridge.leader;

/** A lock that at most one bridge instance holds at a time. */
public interface LeaderLock {

    /** Tries to take the lock without waiting. Returns true if this instance holds it afterwards. */
    boolean tryAcquire();

    /** Whether this instance still holds the lock (for example, its database session is still alive). */
    boolean isHeld();

    void release();
}
