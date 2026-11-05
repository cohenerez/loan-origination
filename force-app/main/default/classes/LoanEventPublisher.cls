/**
 * Publishes LoanStatusChanged__e platform events for loan status changes.
 * Events use PublishAfterCommit, so subscribers only see committed changes.
 */
public inherited sharing class LoanEventPublisher {


    @TestVisible
    private static List<LoanStatusChanged__e> published = new List<LoanStatusChanged__e>();

    public static void publishStatusChanges(List<Loan_Application__c> records,
                                            Map<Id, Loan_Application__c> oldMap) {
        List<Loan_Application__c> changed = new List<Loan_Application__c>();
        Set<Id> contactIds = new Set<Id>();

        for (Loan_Application__c loan : records) {
            if (oldMap != null && oldMap.get(loan.Id).Status__c == loan.Status__c) {
                continue;
            }
            changed.add(loan);
            if (loan.Applicant__c != null) {
                contactIds.add(loan.Applicant__c);
            }
        }
        if (changed.isEmpty()) {
            return;
        }

        // System mode: the event payload needs the email regardless of the running user's FLS on Contact
        Map<Id, Contact> contacts = contactIds.isEmpty()
            ? new Map<Id, Contact>()
            : new Map<Id, Contact>([SELECT Id, Email FROM Contact WHERE Id IN :contactIds WITH SYSTEM_MODE]);

        List<LoanStatusChanged__e> events = new List<LoanStatusChanged__e>();
        for (Loan_Application__c loan : changed) {
            Contact applicant = contacts.get(loan.Applicant__c);
            events.add(new LoanStatusChanged__e(
                Loan_Id__c         = loan.Id,
                Old_Status__c      = oldMap == null ? null : oldMap.get(loan.Id).Status__c,
                New_Status__c      = loan.Status__c,
                Amount__c          = loan.Amount__c,
                Applicant_Email__c = applicant?.Email,
                Event_Uuid__c      = UUID.randomUUID().toString()
            ));
        }

        List<Database.SaveResult> results = EventBus.publish(events);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                for (Database.Error err : results[i].getErrors()) {
                    System.debug(LoggingLevel.ERROR, 'Failed to publish LoanStatusChanged__e for '
                        + events[i].Loan_Id__c + ': ' + err.getStatusCode() + ' ' + err.getMessage());
                }
            }
        }
        published.addAll(events);
    }
}
