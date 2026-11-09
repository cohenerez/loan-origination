package com.erez.loans.bridge.checkpoint;

import com.google.protobuf.ByteString;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Base64;
import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * Keeps the replay ID in PostgreSQL, so it survives the loss of a container or a whole server and is
 * shared by every bridge instance: whichever instance becomes leader resumes from the same position.
 *
 * <p>Only the leader writes, so a plain update-then-insert is enough; no upsert syntax is needed,
 * which also keeps the SQL portable for the H2 tests.
 */
public class JdbcReplayStore implements ReplayStore {

    private final JdbcTemplate jdbc;
    private final String subscriptionId;

    public JdbcReplayStore(JdbcTemplate jdbc, String subscriptionId) {
        this.jdbc = jdbc;
        this.subscriptionId = subscriptionId;
    }

    @Override
    public Optional<ByteString> load() {
        List<String> rows = jdbc.queryForList(
                "SELECT replay_id FROM bridge_checkpoint WHERE subscription_id = ?", String.class, subscriptionId);
        if (rows.isEmpty()) {
            return Optional.empty();
        }
        return Optional.of(ByteString.copyFrom(Base64.getDecoder().decode(rows.get(0))));
    }

    @Override
    public void save(ByteString replayId) {
        String encoded = Base64.getEncoder().encodeToString(replayId.toByteArray());
        OffsetDateTime now = OffsetDateTime.now(ZoneOffset.UTC);
        int updated = jdbc.update(
                "UPDATE bridge_checkpoint SET replay_id = ?, updated_at = ? WHERE subscription_id = ?",
                encoded, now, subscriptionId);
        if (updated == 0) {
            jdbc.update("INSERT INTO bridge_checkpoint (subscription_id, replay_id, updated_at) VALUES (?, ?, ?)",
                    subscriptionId, encoded, now);
        }
    }
}
