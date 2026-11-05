/**
 * Loan details are locked after Submitted, applications can be returned for changes,
 * and credit results can only be written by the credit scoring service.
 */
@IsTest
private class LoanApplicationLockTest {

    private static final String OFFICER_USERNAME =
            'lock.officer.' + UserInfo.getOrganizationId() + '@test.example.com';

    @TestSetup
    static void setup() {
        User officer = new User(
                ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
                Username = OFFICER_USERNAME,
                LastName = 'Officer',
                FirstName = 'Lock',
                Email = 'lock.officer@test.example.com',
                Alias = 'lkoffcr',
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
        System.runAs(officer) {
            insert new Contact(FirstName = 'Dana', LastName = 'Levi', Email = 'dana.levi@example.com');
        }
    }

    private static User officer() {
        return [SELECT Id FROM User WHERE Username = :OFFICER_USERNAME LIMIT 1];
    }

    private static Loan_Application__c newLoan() {
        Loan_Application__c loan = new Loan_Application__c(
                Applicant__c = [SELECT Id FROM Contact LIMIT 1].Id,
                Amount__c = 100000,
                Term_Months__c = 60,
                Monthly_Income__c = 15000,
                Purpose__c = 'Personal'
        );
        insert loan;
        return loan;
    }

    private static void moveTo(Loan_Application__c loan, String status) {
        loan.Status__c = status;
        update loan;
    }

    /**
     * Walks a loan to Pending Approval with credit results, the way the scoring job leaves it.
     * Moving through Scoring queues the scoring job; the mock keeps any callout harmless.
     */
    private static Loan_Application__c pendingApprovalLoan() {
        Test.setMock(System.HttpCalloutMock.class, new CreditScoringCalloutMock());
        Loan_Application__c loan = newLoan();
        moveTo(loan, LoanStatusMachine.SUBMITTED);
        moveTo(loan, LoanStatusMachine.SCORING);

        LoanApplicationTriggerHandler.allowCreditResultUpdates(true);
        loan.Status__c = LoanStatusMachine.PENDING_APPROVAL;
        loan.Credit_Score__c = 700;
        loan.Risk_Tier__c = 'B';
        loan.Approval_Level__c = 'Branch_Manager';
        update loan;
        LoanApplicationTriggerHandler.allowCreditResultUpdates(false);
        return loan;
    }

    private static Loan_Application__c reload(Id loanId) {
        return [SELECT Status__c, Amount__c, Credit_Score__c, Risk_Tier__c, Approval_Level__c, Submitted_Date__c
                FROM Loan_Application__c WHERE Id = :loanId];
    }

    private static String firstError(Database.SaveResult result) {
        return result.getErrors().isEmpty() ? '' : result.getErrors()[0].getMessage();
    }

    @IsTest
    static void detailsAreEditableInDraftAndSubmitted() {
        System.runAs(officer()) {
            Loan_Application__c loan = newLoan();

            Test.startTest();
            loan.Amount__c = 110000;
            update loan;
            moveTo(loan, LoanStatusMachine.SUBMITTED);
            loan.Amount__c = 120000;
            loan.Term_Months__c = 72;
            Database.SaveResult result = Database.update(loan, false);
            Test.stopTest();

            Assert.isTrue(result.isSuccess(), firstError(result));
            Assert.areEqual(120000, reload(loan.Id).Amount__c.intValue());
        }
    }

    @IsTest
    static void detailsAreLockedInPendingApproval() {
        System.runAs(officer()) {
            Loan_Application__c loan;
            Database.SaveResult result;

            Test.startTest();
            loan = pendingApprovalLoan();
            loan.Amount__c = 250000;
            result = Database.update(loan, false);
            Test.stopTest();

            Assert.isFalse(result.isSuccess());
            Assert.isTrue(firstError(result).contains('Return it to Submitted first'), firstError(result));
            Assert.areEqual(100000, reload(loan.Id).Amount__c.intValue());
        }
    }

    @IsTest
    static void detailsAreLockedInFinalStatuses() {
        System.runAs(officer()) {
            Loan_Application__c loan;
            Database.SaveResult result;

            Test.startTest();
            loan = pendingApprovalLoan();
            moveTo(loan, LoanStatusMachine.APPROVED);
            loan.Monthly_Income__c = 50000;
            result = Database.update(loan, false);
            Test.stopTest();

            Assert.isFalse(result.isSuccess());
            Assert.isTrue(firstError(result).contains('while the application is Approved'), firstError(result));
        }
    }

    @IsTest
    static void returnForChangesClearsCreditResults() {
        System.runAs(officer()) {
            Loan_Application__c loan;

            Test.startTest();
            loan = pendingApprovalLoan();
            moveTo(loan, LoanStatusMachine.SUBMITTED);
            Test.stopTest();

            Loan_Application__c result = reload(loan.Id);
            Assert.areEqual(LoanStatusMachine.SUBMITTED, result.Status__c);
            Assert.isNull(result.Credit_Score__c);
            Assert.isNull(result.Risk_Tier__c);
            Assert.isNull(result.Approval_Level__c);
            Assert.isNotNull(result.Submitted_Date__c, 'The original submission date is kept');
        }
    }

    @IsTest
    static void customerChangesAmountAfterScoring() {
        System.runAs(officer()) {
            Loan_Application__c loan;
            Database.SaveResult changeAmount;
            Database.SaveResult rescore;

            Test.startTest();
            loan = pendingApprovalLoan();
            moveTo(loan, LoanStatusMachine.SUBMITTED);
            // Fresh records, as from the UI: only the fields the officer changes
            changeAmount = Database.update(new Loan_Application__c(Id = loan.Id, Amount__c = 80000), false);
            rescore = Database.update(
                    new Loan_Application__c(Id = loan.Id, Status__c = LoanStatusMachine.SCORING), false);
            Test.stopTest();

            Assert.isTrue(changeAmount.isSuccess(), firstError(changeAmount));
            Assert.isTrue(rescore.isSuccess(), firstError(rescore));
            Assert.areEqual(80000, reload(loan.Id).Amount__c.intValue());
        }
    }

    @IsTest
    static void returnAndChangeInOneSave() {
        System.runAs(officer()) {
            Loan_Application__c loan;
            Database.SaveResult result;

            Test.startTest();
            loan = pendingApprovalLoan();
            loan.Status__c = LoanStatusMachine.SUBMITTED;
            loan.Amount__c = 90000;
            result = Database.update(loan, false);
            Test.stopTest();

            Assert.isTrue(result.isSuccess(), firstError(result));
            Loan_Application__c saved = reload(loan.Id);
            Assert.areEqual(90000, saved.Amount__c.intValue());
            Assert.isNull(saved.Credit_Score__c);
        }
    }

    @IsTest
    static void creditResultsCannotBeEditedManually() {
        System.runAs(officer()) {
            Loan_Application__c loan = newLoan();

            Test.startTest();
            loan.Credit_Score__c = 850;
            loan.Risk_Tier__c = 'A';
            Database.SaveResult result = Database.update(loan, false);
            Test.stopTest();

            Assert.isFalse(result.isSuccess());
            Assert.isTrue(firstError(result).contains('set by the credit scoring service'), firstError(result));
            Assert.isNull(reload(loan.Id).Credit_Score__c);
        }
    }

    @IsTest
    static void pendingApprovalCanBeReturnedToSubmitted() {
        Assert.isTrue(LoanStatusMachine.canTransition(LoanStatusMachine.PENDING_APPROVAL, LoanStatusMachine.SUBMITTED));
        Assert.isFalse(LoanStatusMachine.canTransition(LoanStatusMachine.APPROVED, LoanStatusMachine.SUBMITTED));
        Assert.isTrue(LoanStatusMachine.EDITABLE_STATES.contains(LoanStatusMachine.SUBMITTED));
        Assert.isFalse(LoanStatusMachine.EDITABLE_STATES.contains(LoanStatusMachine.PENDING_APPROVAL));
    }
}
