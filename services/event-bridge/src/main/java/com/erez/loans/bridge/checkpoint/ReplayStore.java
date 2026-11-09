package com.erez.loans.bridge.checkpoint;

import com.google.protobuf.ByteString;
import java.util.Optional;

/** Remembers the replay ID of the last event that was safely forwarded. */
public interface ReplayStore {

    Optional<ByteString> load();

    void save(ByteString replayId);
}
