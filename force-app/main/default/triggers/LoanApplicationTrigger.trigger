trigger LoanApplicationTrigger on Loan_Application__c (
    before insert, before update, after insert, after update
) {
    new LoanApplicationTriggerHandler(Trigger.new, Trigger.oldMap, Trigger.operationType).run();
}
