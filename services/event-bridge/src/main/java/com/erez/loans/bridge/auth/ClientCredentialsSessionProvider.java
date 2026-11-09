package com.erez.loans.bridge.auth;

import com.erez.loans.bridge.config.BridgeProperties;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.util.StringUtils;
import org.springframework.web.client.RestClient;

/**
 * Logs in with the OAuth 2.0 client credentials flow of an External Client App. The token response
 * carries the instance URL and an identity URL ending in /id/{orgId}/{userId}, from which the
 * tenant ID is taken.
 */
@Component
public class ClientCredentialsSessionProvider implements SessionProvider {

    private static final Logger log = LoggerFactory.getLogger(ClientCredentialsSessionProvider.class);

    private final BridgeProperties.Salesforce config;
    private final RestClient restClient;
    private volatile SalesforceSession session;

    public ClientCredentialsSessionProvider(BridgeProperties properties, RestClient.Builder builder) {
        this.config = properties.salesforce();
        this.restClient = builder.build();
    }

    @Override
    public synchronized SalesforceSession current() {
        if (session == null) {
            session = login();
        }
        return session;
    }

    @Override
    public synchronized void invalidate() {
        session = null;
    }

    private SalesforceSession login() {
        if (!StringUtils.hasText(config.loginUrl()) || !StringUtils.hasText(config.clientId())
                || !StringUtils.hasText(config.clientSecret())) {
            throw new IllegalStateException(
                    "Set bridge.salesforce.login-url, client-id and client-secret (SF_LOGIN_URL, SF_CLIENT_ID, SF_CLIENT_SECRET)");
        }
        MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("grant_type", "client_credentials");
        form.add("client_id", config.clientId());
        form.add("client_secret", config.clientSecret());

        TokenResponse token = restClient.post()
                .uri(stripTrailingSlash(config.loginUrl()) + "/services/oauth2/token")
                .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                .body(form)
                .retrieve()
                .body(TokenResponse.class);
        if (token == null || token.accessToken() == null) {
            throw new IllegalStateException("Salesforce returned no access token");
        }
        String tenantId = tenantIdFrom(token.identityUrl());
        log.info("Logged in to Salesforce {} (org {})", token.instanceUrl(), tenantId);
        return new SalesforceSession(token.accessToken(), token.instanceUrl(), tenantId);
    }

    /** https://login.salesforce.com/id/00Dxx0000000001EAA/005xx000001X8UzAAK -> 00Dxx0000000001EAA */
    static String tenantIdFrom(String identityUrl) {
        if (identityUrl == null) {
            throw new IllegalStateException("Token response has no identity URL");
        }
        String[] parts = identityUrl.split("/");
        for (int i = 0; i < parts.length - 1; i++) {
            if ("id".equals(parts[i])) {
                return parts[i + 1];
            }
        }
        throw new IllegalStateException("Cannot read the org ID from " + identityUrl);
    }

    private static String stripTrailingSlash(String url) {
        return url.endsWith("/") ? url.substring(0, url.length() - 1) : url;
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    record TokenResponse(
            @JsonProperty("access_token") String accessToken,
            @JsonProperty("instance_url") String instanceUrl,
            @JsonProperty("id") String identityUrl) {
    }
}
