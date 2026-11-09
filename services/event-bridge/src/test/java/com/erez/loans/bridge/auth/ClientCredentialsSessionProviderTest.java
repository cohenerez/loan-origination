package com.erez.loans.bridge.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

class ClientCredentialsSessionProviderTest {

    @Test
    void readsTheOrgIdFromTheIdentityUrl() {
        assertThat(ClientCredentialsSessionProvider.tenantIdFrom(
                "https://login.salesforce.com/id/00Ddi00000G6rEwEAJ/005di00000S35flAAB"))
                .isEqualTo("00Ddi00000G6rEwEAJ");
    }

    @Test
    void rejectsAMissingIdentityUrl() {
        assertThatThrownBy(() -> ClientCredentialsSessionProvider.tenantIdFrom(null))
                .isInstanceOf(IllegalStateException.class);
    }
}
