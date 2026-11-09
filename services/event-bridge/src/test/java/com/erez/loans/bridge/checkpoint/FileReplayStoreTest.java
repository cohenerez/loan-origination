package com.erez.loans.bridge.checkpoint;

import static org.assertj.core.api.Assertions.assertThat;

import com.google.protobuf.ByteString;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class FileReplayStoreTest {

    @TempDir
    Path dir;

    @Test
    void emptyWhenNothingSaved() {
        assertThat(new FileReplayStore(dir.resolve("replay-id")).load()).isEmpty();
    }

    @Test
    void savesAndLoadsBinaryReplayIds() {
        FileReplayStore store = new FileReplayStore(dir.resolve("nested/replay-id"));
        ByteString replayId = ByteString.copyFrom(new byte[] {0, 1, 2, (byte) 250, (byte) 255});

        store.save(replayId);

        assertThat(new FileReplayStore(dir.resolve("nested/replay-id")).load()).contains(replayId);
    }

    @Test
    void ignoresACorruptFile() throws Exception {
        Path file = dir.resolve("replay-id");
        Files.writeString(file, "not base64 !!!");

        assertThat(new FileReplayStore(file).load()).isEmpty();
    }
}
