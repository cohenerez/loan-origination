package com.erez.loans.bridge.kafka;

/** Where decoded events go. Must return only once the event is durably stored. */
public interface EventSink {

    void publish(LoanStatusEvent event) throws Exception;
}
