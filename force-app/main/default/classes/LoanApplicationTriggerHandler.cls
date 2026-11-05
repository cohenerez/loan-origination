/**
 * Trigger handler for Loan_Application__c.
 * Before: enforces the status state machine, locks loan details after Submitted, protects
 *         credit results from manual edits, and stamps lifecycle dates.
 * After:  publishes LoanStatusChanged__e for every status change, and queues credit scoring
 *         for applications that moved to Scoring.
 */
public inherited sharing class LoanApplicationTriggerHandler {

    @TestVisible
    private static Boolean bypass = false;

    public static void bypassOn()  { bypass = true; }
    public static void bypassOff() { bypass = false; }

    /** Loan details that are locked once the application leaves Draft/Submitted. */
    private static final List<SObjectField> LOAN_DETAIL_FIELDS = new List<SObjectField>{
            Loan_Application__c.Applicant__c,
            Loan_Application__c.Amount__c,
            Loan_Application__c.Term_Months__c,
            Loan_Application__c.Monthly_Income__c,
            Loan_Application__c.Purpose__c
    };

    /** Credit results that only the credit scoring service may set. */
    private static final List<SObjectField> CREDIT_RESULT_FIELDS = new List<SObjectField>{
            Loan_Application__c.Credit_Score__c,
            Loan_Application__c.Risk_Tier__c,
            Loan_Application__c.Approval_Level__c
    };

    private static Boolean creditResultUpdatesAllowed = false;

    /** Called by CreditScoringJob around its updates, so it may write the credit results. */
    public static void allowCreditResultUpdates(Boolean allowed) {
        creditResultUpdatesAllowed = allowed;
    }

    private final List<Loan_Application__c> newRecords;
    private final Map<Id, Loan_Application__c> oldMap;
    private final System.TriggerOperation operation;

    public LoanApplicationTriggerHandler(List<Loan_Application__c> newRecords,
            Map<Id, Loan_Application__c> oldMap,
            System.TriggerOperation operation) {
        this.newRecords = newRecords;
        this.oldMap = oldMap;
        this.operation = operation;
    }

    public void run() {
        if (bypass) {
            return;
        }
        switch on operation {
            when BEFORE_INSERT {
                beforeInsert(newRecords);
            }
            when BEFORE_UPDATE {
                beforeUpdate(newRecords, oldMap);
            }
            when AFTER_INSERT {
                LoanEventPublisher.publishStatusChanges(newRecords, null);
            }
            when AFTER_UPDATE {
                LoanEventPublisher.publishStatusChanges(newRecords, oldMap);
                enqueueCreditScoring(newRecords, oldMap);
            }
        }
    }

    private void beforeInsert(List<Loan_Application__c> records) {
        for (Loan_Application__c loan : records) {
            if (String.isBlank(loan.Status__c)) {
                loan.Status__c = LoanStatusMachine.DRAFT;
            }
            if (!LoanStatusMachine.INITIAL_STATES.contains(loan.Status__c)) {
                loan.addError(Loan_Application__c.Status__c,
                        'A new application must start as Draft or Submitted.');
                continue;
            }
            stampDates(loan);
        }
    }

    private void beforeUpdate(List<Loan_Application__c> records, Map<Id, Loan_Application__c> oldMap) {
        for (Loan_Application__c loan : records) {
            Loan_Application__c old = oldMap.get(loan.Id);
            if (!validateFieldChanges(loan, old)) {
                continue;
            }
            if (old.Status__c == loan.Status__c) {
                continue;
            }
            if (!LoanStatusMachine.canTransition(old.Status__c, loan.Status__c)) {
                Set<String> allowed = LoanStatusMachine.allowedFrom(old.Status__c);
                loan.addError(Loan_Application__c.Status__c, String.format(
                        'Cannot change status from {0} to {1}. Allowed: {2}.',
                        new List<Object>{ old.Status__c, loan.Status__c,
                                allowed.isEmpty() ? 'none (final status)' : String.join(new List<String>(allowed), ', ') }));
                continue;
            }
            if (loan.Status__c == LoanStatusMachine.REJECTED && String.isBlank(loan.Decision_Reason__c)) {
                loan.addError(Loan_Application__c.Decision_Reason__c,
                        'A decision reason is required when rejecting an application.');
                continue;
            }
            if (old.Status__c == LoanStatusMachine.PENDING_APPROVAL && loan.Status__c == LoanStatusMachine.SUBMITTED) {
                clearCreditResults(loan);
            }
            stampDates(loan);
        }
    }

    /**
     * Loan details may change only while the application is (or is being returned to) Draft or Submitted,
     * so a score or an approval can never refer to different numbers than the ones on the record.
     * Credit results may only be written by the credit scoring service.
     */
    private Boolean validateFieldChanges(Loan_Application__c loan, Loan_Application__c old) {
        Boolean detailsEditable = LoanStatusMachine.EDITABLE_STATES.contains(old.Status__c)
                || LoanStatusMachine.EDITABLE_STATES.contains(loan.Status__c);
        Boolean valid = true;
        if (!detailsEditable) {
            for (SObjectField field : LOAN_DETAIL_FIELDS) {
                if (loan.get(field) != old.get(field)) {
                    loan.addError(field, 'Loan details can\'t be changed while the application is '
                            + old.Status__c + '. Return it to Submitted first.');
                    valid = false;
                }
            }
        }
        if (!creditResultUpdatesAllowed) {
            for (SObjectField field : CREDIT_RESULT_FIELDS) {
                if (loan.get(field) != old.get(field)) {
                    loan.addError(field, 'Credit results are set by the credit scoring service and can\'t be edited.');
                    valid = false;
                }
            }
        }
        return valid;
    }

    /** A returned application must be scored again, so the old results no longer apply. */
    private void clearCreditResults(Loan_Application__c loan) {
        for (SObjectField field : CREDIT_RESULT_FIELDS) {
            loan.put(field, null);
        }
    }

    private void enqueueCreditScoring(List<Loan_Application__c> records, Map<Id, Loan_Application__c> oldMap) {
        Set<Id> toScore = new Set<Id>();
        for (Loan_Application__c loan : records) {
            if (loan.Status__c == LoanStatusMachine.SCORING
                    && oldMap.get(loan.Id).Status__c != LoanStatusMachine.SCORING) {
                toScore.add(loan.Id);
            }
        }
        if (toScore.isEmpty()) {
            return;
        }
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            System.debug(LoggingLevel.ERROR, 'Queueable limit reached; credit scoring not queued for ' + toScore);
            return;
        }
        System.enqueueJob(new CreditScoringJob(toScore));
    }

    private void stampDates(Loan_Application__c loan) {
        if (loan.Status__c == LoanStatusMachine.SUBMITTED && loan.Submitted_Date__c == null) {
            loan.Submitted_Date__c = System.now();
        }
        if (LoanStatusMachine.DECISION_STATES.contains(loan.Status__c)) {
            loan.Decision_Date__c = System.now();
        }
    }
}
