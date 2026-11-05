/**
 * Tests run as a dedicated Loan Officer user (Standard User + Loan_Officer permission set),
 * so results don't depend on who runs them or on the running user's profile FLS.
 */
@IsTest
private class LoanApplicationTriggerTest {

    private static final String OFFICER_USERNAME =
            'loan.officer.' + UserInfo.getOrganizationId() + '@test.example.com';

    @TestSetup
    static void setup() {
        User officer = new User(
                ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
                Username = OFFICER_USERNAME,
                LastName = 'Officer',
                FirstName = 'Loan',
                Email = 'loan.officer@test.example.com',
                Alias = 'lofficer',
                TimeZoneSidKey = 'Asia/Jerusalem',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US'
        );
        insert officer;
        insert new PermissionSetAssignment(
                AssigneeId = officer.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Loan_Officer' LIMIT 1].Id
        );

        // Created as the officer so they own (and can see) the applicant; also avoids mixed DML
        System.runAs(officer) {
            insert new Contact(FirstName = 'Dana', LastName = 'Levi', Email = 'dana.levi@example.com');
        }
    }

    private static User officer() {
        return [SELECT Id FROM User WHERE Username = :OFFICER_USERNAME LIMIT 1];
    }

    private static Id applicantId() {
        return [SELECT Id FROM Contact LIMIT 1].Id;
    }

    private static Loan_Application__c newLoan() {
        return new Loan_Application__c(
                Applicant__c = applicantId(),
                Amount__c = 100000,
                Term_Months__c = 60,
                Monthly_Income__c = 15000,
                Purpose__c = 'Personal'
        );
    }

    private static Loan_Application__c reload(Id loanId) {
        return [SELECT Status__c, Submitted_Date__c, Decision_Date__c
        FROM Loan_Application__c WHERE Id = :loanId];
    }

    private static void moveTo(Loan_Application__c loan, String status) {
        loan.Status__c = status;
        update loan;
    }

    @IsTest
    static void newLoanDefaultsToDraftAndPublishesEvent() {
        System.runAs(officer()) {
            Loan_Application__c loan = newLoan();

            Test.startTest();
            insert loan;
            Test.stopTest();

            Assert.areEqual(LoanStatusMachine.DRAFT, reload(loan.Id).Status__c);
            Assert.areEqual(1, LoanEventPublisher.published.size());
            LoanStatusChanged__e evt = LoanEventPublisher.published[0];
            Assert.isNull(evt.Old_Status__c);
            Assert.areEqual(LoanStatusMachine.DRAFT, evt.New_Status__c);
            Assert.areEqual('dana.levi@example.com', evt.Applicant_Email__c);
            Assert.areEqual(36, evt.Event_Uuid__c.length());
        }
    }

    @IsTest
    static void submitStampsDateAndPublishesTransition() {
        System.runAs(officer()) {
            Loan_Application__c loan = newLoan();
            insert loan;
            LoanEventPublisher.published.clear();

            Test.startTest();
            moveTo(loan, LoanStatusMachine.SUBMITTED);
            Test.stopTest();

            Assert.isNotNull(reload(loan.Id).Submitted_Date__c);
            Assert.areEqual(1, LoanEventPublisher.published.size());
            Assert.areEqual(LoanStatusMachine.DRAFT, LoanEventPublisher.published[0].Old_Status__c);
            Assert.areEqual(LoanStatusMachine.SUBMITTED, LoanEventPublisher.published[0].New_Status__c);
        }
    }

    @IsTest
    static void invalidTransitionIsBlocked() {
        System.runAs(officer()) {
            Loan_Application__c loan = newLoan();
            insert loan;

            Test.startTest();
            try {
                moveTo(loan, LoanStatusMachine.APPROVED);
                Assert.fail('Draft -> Approved should be rejected');
            } catch (DmlException e) {
                Assert.isTrue(e.getMessage().contains('Cannot change status from Draft to Approved'), e.getMessage());
            }
            Test.stopTest();

            Assert.areEqual(LoanStatusMachine.DRAFT, reload(loan.Id).Status__c);
        }
    }

    @IsTest
    static void insertWithNonInitialStatusIsBlocked() {
        System.runAs(officer()) {
            Loan_Application__c loan = newLoan();
            loan.Status__c = LoanStatusMachine.APPROVED;

            Test.startTest();
            Database.SaveResult result = Database.insert(loan, false);
            Test.stopTest();

            Assert.isFalse(result.isSuccess());
            String message = result.getErrors()[0].getMessage();
            Assert.isTrue(message.contains('must start as Draft or Submitted'), message);
        }
    }

    @IsTest
    static void rejectRequiresDecisionReason() {
        System.runAs(officer()) {
            Loan_Application__c loan = newLoan();
            insert loan;
            moveTo(loan, LoanStatusMachine.SUBMITTED);
            moveTo(loan, LoanStatusMachine.SCORING);

            Test.startTest();
            loan.Status__c = LoanStatusMachine.REJECTED;
            Database.SaveResult withoutReason = Database.update(loan, false);

            loan.Decision_Reason__c = 'Credit score below minimum threshold';
            Database.SaveResult withReason = Database.update(loan, false);
            Test.stopTest();

            Assert.isFalse(withoutReason.isSuccess());
            String message = withoutReason.getErrors()[0].getMessage();
            Assert.isTrue(message.contains('decision reason is required'), message);
            Assert.isTrue(withReason.isSuccess());
            Assert.isNotNull(reload(loan.Id).Decision_Date__c);
        }
    }

    @IsTest
    static void happyPathReachesFunded() {
        System.runAs(officer()) {
            Loan_Application__c loan = newLoan();
            insert loan;

            Test.startTest();
            moveTo(loan, LoanStatusMachine.SUBMITTED);
            moveTo(loan, LoanStatusMachine.SCORING);
            moveTo(loan, LoanStatusMachine.PENDING_APPROVAL);
            moveTo(loan, LoanStatusMachine.APPROVED);
            moveTo(loan, LoanStatusMachine.FUNDED);
            Test.stopTest();

            Loan_Application__c result = reload(loan.Id);
            Assert.areEqual(LoanStatusMachine.FUNDED, result.Status__c);
            Assert.isNotNull(result.Decision_Date__c);
            // insert + 5 transitions
            Assert.areEqual(6, LoanEventPublisher.published.size());
        }
    }

    @IsTest
    static void nonStatusChangeDoesNotPublish() {
        System.runAs(officer()) {
            Loan_Application__c loan = newLoan();
            insert loan;
            LoanEventPublisher.published.clear();

            Test.startTest();
            loan.Amount__c = 120000;
            update loan;
            Test.stopTest();

            Assert.areEqual(0, LoanEventPublisher.published.size());
        }
    }

    @IsTest
    static void bulkSubmitOf200() {
        System.runAs(officer()) {
            Id contactId = applicantId();
            List<Loan_Application__c> loans = new List<Loan_Application__c>();
            for (Integer i = 0; i < 200; i++) {
                loans.add(new Loan_Application__c(Applicant__c = contactId, Amount__c = 10000 + i, Term_Months__c = 36));
            }
            insert loans;
            LoanEventPublisher.published.clear();

            Test.startTest();
            for (Loan_Application__c loan : loans) {
                loan.Status__c = LoanStatusMachine.SUBMITTED;
            }
            update loans;
            Test.stopTest();

            Assert.areEqual(200, LoanEventPublisher.published.size());
            Assert.areEqual(200, [SELECT COUNT() FROM Loan_Application__c
            WHERE Status__c = :LoanStatusMachine.SUBMITTED AND Submitted_Date__c != null]);
        }
    }

    @IsTest
    static void bypassSkipsHandler() {
        System.runAs(officer()) {
            Loan_Application__c loan = newLoan();
            loan.Status__c = LoanStatusMachine.APPROVED;

            Test.startTest();
            LoanApplicationTriggerHandler.bypassOn();
            insert loan;
            LoanApplicationTriggerHandler.bypassOff();
            Test.stopTest();

            Assert.areEqual(LoanStatusMachine.APPROVED, reload(loan.Id).Status__c);
            Assert.areEqual(0, LoanEventPublisher.published.size());
        }
    }

    @IsTest
    static void stateMachineRules() {
        Assert.isTrue(LoanStatusMachine.canTransition(LoanStatusMachine.DRAFT, LoanStatusMachine.DRAFT));
        Assert.isTrue(LoanStatusMachine.canTransition(LoanStatusMachine.SCORING, LoanStatusMachine.SUBMITTED));
        Assert.isFalse(LoanStatusMachine.canTransition(LoanStatusMachine.FUNDED, LoanStatusMachine.DRAFT));
        Assert.isFalse(LoanStatusMachine.canTransition('Unknown', LoanStatusMachine.DRAFT));
        Assert.isTrue(LoanStatusMachine.allowedFrom(LoanStatusMachine.REJECTED).isEmpty());
        Assert.isTrue(LoanStatusMachine.allowedFrom('Unknown').isEmpty());
    }
}