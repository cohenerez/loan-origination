package com.erez.loans.bridge.leader;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import javax.sql.DataSource;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Leader lock built on a PostgreSQL session-level advisory lock.
 *
 * <p>The lock belongs to one database session, so this class keeps a dedicated connection open for as
 * long as it is leader. If the instance crashes or loses its connection, PostgreSQL ends the session
 * and releases the lock, and a standby instance can take it. No extra infrastructure (ZooKeeper,
 * Kubernetes leases) is needed: the database the bridge already uses is the coordinator.
 */
public class PostgresAdvisoryLock implements LeaderLock {

    private static final Logger log = LoggerFactory.getLogger(PostgresAdvisoryLock.class);
    private static final int VALIDATION_TIMEOUT_SECONDS = 2;

    private final DataSource dataSource;
    private final long key;
    private Connection connection;

    public PostgresAdvisoryLock(DataSource dataSource, long key) {
        this.dataSource = dataSource;
        this.key = key;
    }

    @Override
    public synchronized boolean tryAcquire() {
        if (connection != null) {
            return isHeld();
        }
        Connection candidate = null;
        try {
            candidate = dataSource.getConnection();
            try (PreparedStatement statement = candidate.prepareStatement("SELECT pg_try_advisory_lock(?)")) {
                statement.setLong(1, key);
                try (ResultSet result = statement.executeQuery()) {
                    if (result.next() && result.getBoolean(1)) {
                        connection = candidate;
                        return true;
                    }
                }
            }
            closeQuietly(candidate);
            return false;
        } catch (SQLException e) {
            log.warn("Could not try the leader lock: {}", e.getMessage());
            closeQuietly(candidate);
            return false;
        }
    }

    @Override
    public synchronized boolean isHeld() {
        if (connection == null) {
            return false;
        }
        try {
            if (connection.isValid(VALIDATION_TIMEOUT_SECONDS)) {
                return true;
            }
        } catch (SQLException e) {
            log.warn("Leader lock connection check failed: {}", e.getMessage());
        }
        // Session gone, so PostgreSQL has released the lock
        closeQuietly(connection);
        connection = null;
        return false;
    }

    @Override
    public synchronized void release() {
        if (connection == null) {
            return;
        }
        try (PreparedStatement statement = connection.prepareStatement("SELECT pg_advisory_unlock(?)")) {
            statement.setLong(1, key);
            statement.execute();
        } catch (SQLException e) {
            log.warn("Could not release the leader lock cleanly: {}", e.getMessage());
        } finally {
            closeQuietly(connection);
            connection = null;
        }
    }

    private static void closeQuietly(Connection c) {
        if (c == null) {
            return;
        }
        try {
            c.close();
        } catch (SQLException ignored) {
            // nothing more to do
        }
    }
}
