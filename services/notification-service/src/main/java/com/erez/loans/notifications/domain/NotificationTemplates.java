package com.erez.loans.notifications.domain;

import com.erez.loans.notifications.config.NotificationProperties;
import com.erez.loans.notifications.messaging.LoanStatusEvent;
import java.math.BigDecimal;
import java.text.NumberFormat;
import java.util.Locale;
import java.util.Optional;
import org.springframework.stereotype.Component;


@Component
public class NotificationTemplates {

    private final String bankName;

    public NotificationTemplates(NotificationProperties properties) {
        this.bankName = properties.bankName();
    }

    public Optional<EmailMessage> forEvent(LoanStatusEvent event) {
        String amount = formatAmount(event.amount());
        String reference = reference(event.loanId());
        return Optional.ofNullable(switch (event.newStatus() == null ? "" : event.newStatus()) {
            case "Submitted" -> new EmailMessage(
                    "We received your loan application " + reference,
                    body("Thank you for applying for a loan of " + amount + ". We received your application and"
                            + " will assess it shortly. Your reference is " + reference + "."));
            case "Pending_Approval" -> new EmailMessage(
                    "Your loan application " + reference + " is under review",
                    body("Good news: your application for " + amount + " passed our initial credit assessment"
                            + " and is now with our approval team. We'll let you know as soon as a decision is made."));
            case "Approved" -> new EmailMessage(
                    "Your loan of " + amount + " is approved",
                    body("Congratulations! Your loan application " + reference + " for " + amount
                            + " has been approved. Your loan officer will contact you about the next steps."));
            case "Rejected" -> new EmailMessage(
                    "An update on your loan application " + reference,
                    body("Thank you for your application for " + amount + ". After careful review, we are unable"
                            + " to approve it at this time. Your loan officer can explain the decision and discuss"
                            + " other options with you."));
            case "Funded" -> new EmailMessage(
                    "Your loan of " + amount + " has been funded",
                    body("The funds for your loan " + reference + " (" + amount + ") have been released to your"
                            + " account. Thank you for choosing " + bankName + "."));
            default -> null;
        });
    }

    private String body(String text) {
        return "Hello,\n\n" + text + "\n\nKind regards,\n" + bankName + "\n";
    }

    static String formatAmount(BigDecimal amount) {
        if (amount == null) {
            return "your requested amount";
        }
        NumberFormat format = NumberFormat.getCurrencyInstance(Locale.US);
        format.setMaximumFractionDigits(0);
        return format.format(amount);
    }


    static String reference(String loanId) {
        if (loanId == null || loanId.length() < 6) {
            return "#" + loanId;
        }
        return "#" + loanId.substring(loanId.length() - 6).toUpperCase(Locale.ROOT);
    }
}
