package com.erez.loans.bridge.checkpoint;

import static org.assertj.core.api.Assertions.assertThat;

import com.google.protobuf.ByteString;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.JdbcTest;
import org.springframework.jdbc.core.JdbcTemplate;

/** Runs the Flyway migration on an embedded database and checks the checkpoint round-trip. */
@JdbcTest
class JdbcReplayStoreTest {

    private static final String TOPIC = "/event/LoanStatusChanged__e";

    @Autowired
    private JdbcTemplate jdbc;

    @Test
    void emptyWhenNothingSaved() {
        assertThat(new JdbcReplayStore(jdbc, TOPIC).load()).isEmpty();
    }

    @Test
    void savesAndLoadsBinaryReplayIds() {
        ByteString replayId = ByteString.copyFrom(new byte[] {0, 1, 2, (byte) 250, (byte) 255});

        new JdbcReplayStore(jdbc, TOPIC).save(replayId);

        // A new instance (another bridge process) reads the same position
        assertThat(new JdbcReplayStore(jdbc, TOPIC).load()).contains(replayId);
    }

    @Test
    void laterSavesReplaceTheEarlierPosition() {
        JdbcReplayStore store = new JdbcReplayStore(jdbc, TOPIC);
        store.save(ByteString.copyFromUtf8("first"));
        store.save(ByteString.copyFromUtf8("second"));

        assertThat(store.load()).contains(ByteString.copyFromUtf8("second"));
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM bridge_checkpoint", Integer.class)).isEqualTo(1);
    }

    @Test
    void eachTopicHasItsOwnPosition() {
        new JdbcReplayStore(jdbc, TOPIC).save(ByteString.copyFromUtf8("loans"));
        new JdbcReplayStore(jdbc, "/event/Other__e").save(ByteString.copyFromUtf8("other"));

        assertThat(new JdbcReplayStore(jdbc, TOPIC).load()).contains(ByteString.copyFromUtf8("loans"));
    }
}
