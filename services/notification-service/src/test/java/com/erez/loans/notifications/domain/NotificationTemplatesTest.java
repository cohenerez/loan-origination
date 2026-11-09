package com.erez.loans.notifications.domain;

import static org.assertj.core.api.Assertions.assertThat;

import com.erez.loans.notifications.config.NotificationProperties;
import com.erez.loans.notifications.messaging.LoanStatusEvent;
import java.math.BigDecimal;
import org.junit.jupiter.api.Test;

class NotificationTemplatesTest {

    private final NotificationTemplates templates =
            new NotificationTemplates(new NotificationProperties("loan-events", "loans@bank.example", "Erez Bank"));

    private static LoanStatusEvent event(String newStatus) {
        return new LoanStatusEvent("u-1", "a01di00001O3s0jAAB", "Scoring", newStatus,
                new BigDecimal("150000"), "dana@example.com", null, null);
    }

    @Test
    void approvedEmailMentionsTheAmount() {
        EmailMessage message = templates.forEvent(event("Approved")).orElseThrow();

        assertThat(message.subject()).isEqualTo("Your loan of $150,000 is approved");
        assertThat(message.body()).contains("Congratulations").contains("#S0JAAB").endsWith("Erez Bank\n");
    }

    @Test
    void everyCustomerFacingStatusHasATemplate() {
        for (String status : new String[] {"Submitted", "Pending_Approval", "Approved", "Rejected", "Funded"}) {
            assertThat(templates.forEvent(event(status))).as(status).isPresent();
        }
    }

    @Test
    void internalStatusesSendNothing() {
        assertThat(templates.forEvent(event("Draft"))).isEmpty();
        assertThat(templates.forEvent(event("Scoring"))).isEmpty();
        assertThat(templates.forEvent(event(null))).isEmpty();
    }

    @Test
    void rejectionDoesNotRevealInternalDetails() {
        String body = templates.forEvent(event("Rejected")).orElseThrow().body().toLowerCase();

        assertThat(body).doesNotContain("score").doesNotContain("tier").contains("loan officer");
    }

    @Test
    void referenceIsTheEndOfTheRecordId() {
        assertThat(NotificationTemplates.reference("a01di00001O3s0jAAB")).isEqualTo("#S0JAAB");
        assertThat(NotificationTemplates.formatAmount(null)).isEqualTo("your requested amount");
    }
}
