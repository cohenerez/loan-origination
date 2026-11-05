/**
 * Trigger handler for Loan_Application__c.
 * Before: enforces the status state machine and stamps lifecycle dates.
 * After:  publishes LoanStatusChanged__e for every status change.
 */
public inherited sharing class LoanApplicationTriggerHandler {

    @TestVisible
    private static Boolean bypass = false;

    public static void bypassOn()  { bypass = true; }
    public static void bypassOff() { bypass = false; }

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
            String oldStatus = oldMap.get(loan.Id).Status__c;
            if (oldStatus == loan.Status__c) {
                continue;
            }
            if (!LoanStatusMachine.canTransition(oldStatus, loan.Status__c)) {
                Set<String> allowed = LoanStatusMachine.allowedFrom(oldStatus);
                loan.addError(Loan_Application__c.Status__c, String.format(
                    'Cannot change status from {0} to {1}. Allowed: {2}.',
                    new List<Object>{ oldStatus, loan.Status__c,
                        allowed.isEmpty() ? 'none (final status)' : String.join(new List<String>(allowed), ', ') }));
                continue;
            }
            if (loan.Status__c == LoanStatusMachine.REJECTED && String.isBlank(loan.Decision_Reason__c)) {
                loan.addError(Loan_Application__c.Decision_Reason__c,
                    'A decision reason is required when rejecting an application.');
                continue;
            }
            stampDates(loan);
        }
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
