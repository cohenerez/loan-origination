package com.erez.loans.bridge.checkpoint;

import com.google.protobuf.ByteString;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicReference;

/** Test double for the checkpoint. */
public class InMemoryReplayStore implements ReplayStore {

    private final AtomicReference<ByteString> replayId = new AtomicReference<>();

    @Override
    public Optional<ByteString> load() {
        return Optional.ofNullable(replayId.get());
    }

    @Override
    public void save(ByteString value) {
        replayId.set(value);
    }
}
