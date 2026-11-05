/**
 * Scores loan applications that moved to Scoring, by calling the external credit scoring service.
 *
 * - All callouts happen first and all DML afterwards: Apex doesn't allow a callout after DML
 *   in the same transaction.
 * - At most BATCH_SIZE loans per job, so even if every call hits the timeout the job stays
 *   under the 120-second total callout limit. Remaining loans are handled by a chained job.
 * - Every call is recorded as a Credit_Check__c, whatever the outcome.
 * - On success the loan is routed by LoanApprovalRouter; on failure it goes back to Submitted
 *   so it can be sent to scoring again.
 */
public inherited sharing class CreditScoringJob implements Queueable, Database.AllowsCallouts {

    @TestVisible
    static final Integer BATCH_SIZE = 10;

    private final List<Id> loanIds;

    public CreditScoringJob(Set<Id> loanIds) {
        this.loanIds = new List<Id>(loanIds);
    }

    public void execute(QueueableContext context) {
        List<Id> batch = new List<Id>();
        Set<Id> remaining = new Set<Id>();
        for (Integer i = 0; i < loanIds.size(); i++) {
            if (i < BATCH_SIZE) {
                batch.add(loanIds[i]);
            } else {
                remaining.add(loanIds[i]);
            }
        }

        // Only loans still in Scoring: a user may have moved one on since the job was queued
        List<Loan_Application__c> loans = [
                SELECT Id, Amount__c, Term_Months__c, Monthly_Income__c, Purpose__c
                FROM Loan_Application__c
                WHERE Id IN :batch AND Status__c = :LoanStatusMachine.SCORING
        ];

        // 1. Callouts
        CreditScoringClient client = new CreditScoringClient();
        Map<Id, CreditScoringClient.Result> results = new Map<Id, CreditScoringClient.Result>();
        for (Loan_Application__c loan : loans) {
            results.put(loan.Id, scoreLoan(client, loan));
        }

        // 2. DML
        saveResults(loans, results);

        if (!remaining.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new CreditScoringJob(remaining));
        }
    }

    private static CreditScoringClient.Result scoreLoan(CreditScoringClient client, Loan_Application__c loan) {
        String requestId = UUID.randomUUID().toString();
        if (loan.Amount__c == null || loan.Term_Months__c == null || loan.Monthly_Income__c == null) {
            return CreditScoringClient.notSent(requestId,
                    'Amount, term and monthly income are required for credit scoring.');
        }
        CreditScoringClient.ScoreRequest request = new CreditScoringClient.ScoreRequest();
        request.requestId = requestId;
        request.loanId = loan.Id;
        request.amount = loan.Amount__c;
        request.termMonths = loan.Term_Months__c.intValue();
        request.monthlyIncome = loan.Monthly_Income__c;
        request.purpose = loan.Purpose__c;
        return client.score(request);
    }

    private static void saveResults(List<Loan_Application__c> loans, Map<Id, CreditScoringClient.Result> results) {
        LoanApprovalRouter router = new LoanApprovalRouter();
        List<Credit_Check__c> checks = new List<Credit_Check__c>();
        List<Loan_Application__c> updates = new List<Loan_Application__c>();
        List<Loan_Application__c> approvals = new List<Loan_Application__c>();

        for (Loan_Application__c loan : loans) {
            CreditScoringClient.Result result = results.get(loan.Id);
            checks.add(toCreditCheck(loan.Id, result));

            if (!result.isSuccess()) {
                updates.add(new Loan_Application__c(Id = loan.Id, Status__c = LoanStatusMachine.SUBMITTED));
                continue;
            }

            Integer score = result.response.score;
            LoanApprovalRouter.Decision decision = router.route(loan.Amount__c, score);
            Loan_Application__c scored = new Loan_Application__c(
                    Id = loan.Id,
                    Credit_Score__c = score,
                    Risk_Tier__c = result.response.riskTier,
                    Approval_Level__c = decision.approvalLevel
            );
            if (decision.autoApprove) {
                // The state machine only allows Approved after Pending_Approval, so take both steps
                scored.Status__c = LoanStatusMachine.PENDING_APPROVAL;
                approvals.add(new Loan_Application__c(
                        Id = loan.Id, Status__c = LoanStatusMachine.APPROVED, Decision_Reason__c = decision.reason));
            } else {
                scored.Status__c = decision.status;
                scored.Decision_Reason__c = decision.reason;
            }
            updates.add(scored);
        }

        logFailures('Credit_Check__c insert', Database.insert(checks, false));
        LoanApplicationTriggerHandler.allowCreditResultUpdates(true);
        try {
            logFailures('Loan_Application__c update', Database.update(updates, false));
            if (!approvals.isEmpty()) {
                logFailures('Loan_Application__c auto-approval', Database.update(approvals, false));
            }
        } finally {
            LoanApplicationTriggerHandler.allowCreditResultUpdates(false);
        }
    }

    private static Credit_Check__c toCreditCheck(Id loanId, CreditScoringClient.Result result) {
        return new Credit_Check__c(
                Loan_Application__c = loanId,
                Request_Id__c = result.requestId,
                Status__c = result.outcome,
                Score__c = result.isSuccess() ? result.response.score : null,
                Response_Time_Ms__c = result.elapsedMs,
                Error_Message__c = result.errorMessage == null ? null : result.errorMessage.abbreviate(255),
                Raw_Response__c = result.rawBody == null ? null : result.rawBody.left(32768)
        );
    }

    private static void logFailures(String operation, List<Database.SaveResult> saveResults) {
        for (Database.SaveResult saveResult : saveResults) {
            if (!saveResult.isSuccess()) {
                for (Database.Error error : saveResult.getErrors()) {
                    System.debug(LoggingLevel.ERROR, 'CreditScoringJob ' + operation + ' failed for '
                            + saveResult.getId() + ': ' + error.getStatusCode() + ' ' + error.getMessage());
                }
            }
        }
    }
}
