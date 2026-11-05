/**
 * Decides where a scored application goes, using the Approval_Threshold__mdt records:
 * the first threshold (by Sort_Order__c) whose maximum amount covers the loan and whose
 * minimum score the applicant meets decides the approval level. If none matches, the
 * application is rejected. Thresholds can be changed in Setup without a deployment.
 */
public inherited sharing class LoanApprovalRouter {

    public static final String AUTO = 'Auto';

    public class Decision {
        public String status;
        public String approvalLevel;
        public String reason;
        public Boolean autoApprove = false;
    }


    @TestVisible
    private static List<Approval_Threshold__mdt> thresholdsOverride;

    private final List<Approval_Threshold__mdt> thresholds;

    public LoanApprovalRouter() {
        thresholds = new List<Approval_Threshold__mdt>(
                thresholdsOverride != null ? thresholdsOverride : Approval_Threshold__mdt.getAll().values());
        thresholds.sort(new BySortOrder());
    }

    public Decision route(Decimal amount, Integer score) {
        for (Approval_Threshold__mdt threshold : thresholds) {
            Boolean amountCovered = threshold.Max_Amount__c == null || amount <= threshold.Max_Amount__c;
            Boolean scoreMet = threshold.Min_Score__c == null || score >= threshold.Min_Score__c;
            if (amountCovered && scoreMet) {
                return approve(threshold, score);
            }
        }
        Decision rejected = new Decision();
        rejected.status = LoanStatusMachine.REJECTED;
        rejected.reason = 'Automatically rejected: credit score ' + score
                + ' does not meet the minimum required for an amount of ' + amount.format() + '.';
        return rejected;
    }

    private static Decision approve(Approval_Threshold__mdt threshold, Integer score) {
        Decision decision = new Decision();
        decision.approvalLevel = threshold.Approver_Level__c;
        if (threshold.Approver_Level__c == AUTO) {
            decision.autoApprove = true;
            decision.status = LoanStatusMachine.APPROVED;
            decision.reason = 'Auto-approved: credit score ' + score
                    + ' meets the minimum of ' + threshold.Min_Score__c.intValue()
                    + ' for amounts up to ' + threshold.Max_Amount__c.format() + '.';
        } else {
            decision.status = LoanStatusMachine.PENDING_APPROVAL;
        }
        return decision;
    }

    private class BySortOrder implements Comparator<Approval_Threshold__mdt> {
        public Integer compare(Approval_Threshold__mdt a, Approval_Threshold__mdt b) {
            Decimal left = a.Sort_Order__c == null ? 0 : a.Sort_Order__c;
            Decimal right = b.Sort_Order__c == null ? 0 : b.Sort_Order__c;
            return left < right ? -1 : (left > right ? 1 : 0);
        }
    }
}
