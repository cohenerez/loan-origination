package com.erez.loans.bridge.auth;

/** Supplies the current session; implementations cache it and fetch a new one after {@link #invalidate()}. */
public interface SessionProvider {

    SalesforceSession current();

    /** Called when Salesforce rejects the token, so the next call logs in again. */
    void invalidate();
}
