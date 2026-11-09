package com.erez.loans.bridge.auth;

/** What the Pub/Sub API needs on every call: an access token, the org's instance URL and its ID (tenant). */
public record SalesforceSession(String accessToken, String instanceUrl, String tenantId) {
}
