/**
* End-to-end tests for credit scoring: trigger -> Queueable -> callout (mocked) -> Credit_Check__c -> routing.
 * Every test runs as a Loan Officer user (Standard User + Loan_Officer permission set).
 */
@IsTest
public with sharing class CreditScoringJobTest {

    private static final String OFFICER_USERNAME =
            'scoring.officer.' + UserInfo.getOrganizationId() + '@test.example.com';

    @TestSetup
    static void setup() {
        User officer = new User(
                ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
                Username = OFFICER_USERNAME,
                LastName = 'Officer',
                FirstName = 'Scoring',
                Email = 'scoring.officer@test.example.com',
                Alias = 'sofficer',
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

    private static void useTestThresholds() {
        LoanApprovalRouter.thresholdsOverride = new List<Approval_Threshold__mdt>{
                new Approval_Threshold__mdt(Max_Amount__c = 50000, Min_Score__c = 700,
                        Approver_Level__c = 'Auto', Sort_Order__c = 1),
                new Approval_Threshold__mdt(Max_Amount__c = 250000, Min_Score__c = 620,
                        Approver_Level__c = 'Branch_Manager', Sort_Order__c = 2),
                new Approval_Threshold__mdt(Max_Amount__c = 2000000, Min_Score__c = 580,
                        Approver_Level__c = 'Credit_Committee', Sort_Order__c = 3)
        };
    }

    private static CreditScoringCalloutMock mockService() {
        useTestThresholds();
        CreditScoringCalloutMock mock = new CreditScoringCalloutMock();
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    /** Creates submitted loans, ready to be sent to scoring. */
    private static List<Loan_Application__c> submittedLoans(Integer count, Decimal amount) {
        Id applicantId = [SELECT Id FROM Contact LIMIT 1].Id;
        List<Loan_Application__c> loans = new List<Loan_Application__c>();
        for (Integer i = 0; i < count; i++) {
            loans.add(new Loan_Application__c(Applicant__c = applicantId, Amount__c = amount,
                    Term_Months__c = 60, Monthly_Income__c = 15000, Purpose__c = 'Personal'));
        }
        insert loans;
        for (Loan_Application__c loan : loans) {
            loan.Status__c = LoanStatusMachine.SUBMITTED;
        }
        update loans;
        return loans;
    }

    private static void sendToScoring(List<Loan_Application__c> loans) {
        for (Loan_Application__c loan : loans) {
            loan.Status__c = LoanStatusMachine.SCORING;
        }
        update loans;
    }

    private static Loan_Application__c reload(Id loanId) {
        return [SELECT Status__c, Credit_Score__c, Risk_Tier__c, Approval_Level__c,
                Decision_Reason__c, Decision_Date__c
        FROM Loan_Application__c WHERE Id = :loanId];
    }

    private static Credit_Check__c onlyCheck(Id loanId) {
        List<Credit_Check__c> checks = [
                SELECT Request_Id__c, Status__c, Score__c, Error_Message__c, Raw_Response__c, Response_Time_Ms__c
                FROM Credit_Check__c WHERE Loan_Application__c = :loanId
        ];
        Assert.areEqual(1, checks.size(), 'Expected exactly one credit check');
        return checks[0];
    }

    @IsTest
    static void highScoreSmallLoanIsAutoApproved() {
        System.runAs(officer()) {
            CreditScoringCalloutMock mock = mockService();
            mock.score = 760;
            mock.riskTier = 'A';
            Loan_Application__c loan = submittedLoans(1, 30000)[0];

            Test.startTest();
            sendToScoring(new List<Loan_Application__c>{ loan });
            Test.stopTest();

            Loan_Application__c result = reload(loan.Id);
            Assert.areEqual(LoanStatusMachine.APPROVED, result.Status__c);
            Assert.areEqual(760, result.Credit_Score__c.intValue());
            Assert.areEqual('A', result.Risk_Tier__c);
            Assert.areEqual('Auto', result.Approval_Level__c);
            Assert.isTrue(result.Decision_Reason__c.startsWith('Auto-approved'), result.Decision_Reason__c);
            Assert.isNotNull(result.Decision_Date__c);

            Credit_Check__c check = onlyCheck(loan.Id);
            Assert.areEqual(CreditScoringClient.SUCCESS, check.Status__c);
            Assert.areEqual(760, check.Score__c.intValue());
            Assert.isNotNull(check.Raw_Response__c);
        }
    }

    @IsTest
    static void mediumLoanIsRoutedToBranchManager() {
        System.runAs(officer()) {
            CreditScoringCalloutMock mock = mockService();
            mock.score = 690;
            Loan_Application__c loan = submittedLoans(1, 100000)[0];

            Test.startTest();
            sendToScoring(new List<Loan_Application__c>{ loan });
            Test.stopTest();

            Loan_Application__c result = reload(loan.Id);
            Assert.areEqual(LoanStatusMachine.PENDING_APPROVAL, result.Status__c);
            Assert.areEqual('Branch_Manager', result.Approval_Level__c);
            Assert.isNull(result.Decision_Date__c);
        }
    }

    @IsTest
    static void lowScoreIsRejectedWithReason() {
        System.runAs(officer()) {
            CreditScoringCalloutMock mock = mockService();
            mock.score = 550;
            mock.riskTier = 'D';
            Loan_Application__c loan = submittedLoans(1, 100000)[0];

            Test.startTest();
            sendToScoring(new List<Loan_Application__c>{ loan });
            Test.stopTest();

            Loan_Application__c result = reload(loan.Id);
            Assert.areEqual(LoanStatusMachine.REJECTED, result.Status__c);
            Assert.isTrue(result.Decision_Reason__c.startsWith('Automatically rejected'), result.Decision_Reason__c);
            Assert.isNotNull(result.Decision_Date__c);
        }
    }

    @IsTest
    static void serverErrorReturnsLoanToSubmitted() {
        System.runAs(officer()) {
            CreditScoringCalloutMock mock = mockService();
            mock.statusCode = 503;
            Loan_Application__c loan = submittedLoans(1, 100000)[0];

            Test.startTest();
            sendToScoring(new List<Loan_Application__c>{ loan });
            Test.stopTest();

            Assert.areEqual(LoanStatusMachine.SUBMITTED, reload(loan.Id).Status__c);
            Credit_Check__c check = onlyCheck(loan.Id);
            Assert.areEqual(CreditScoringClient.FAILED, check.Status__c);
            Assert.isTrue(check.Error_Message__c.startsWith('HTTP 503'), check.Error_Message__c);
            Assert.isNull(check.Score__c);
        }
    }

    @IsTest
    static void timeoutIsRecordedAsTimeout() {
        System.runAs(officer()) {
            CreditScoringCalloutMock mock = mockService();
            mock.throwTimeout = true;
            Loan_Application__c loan = submittedLoans(1, 100000)[0];

            Test.startTest();
            sendToScoring(new List<Loan_Application__c>{ loan });
            Test.stopTest();

            Assert.areEqual(LoanStatusMachine.SUBMITTED, reload(loan.Id).Status__c);
            Assert.areEqual(CreditScoringClient.TIMEOUT, onlyCheck(loan.Id).Status__c);
        }
    }

    @IsTest
    static void malformedResponseIsRecordedAsFailure() {
        System.runAs(officer()) {
            CreditScoringCalloutMock mock = mockService();
            mock.rawBody = 'this is not json';
            Loan_Application__c loan = submittedLoans(1, 100000)[0];

            Test.startTest();
            sendToScoring(new List<Loan_Application__c>{ loan });
            Test.stopTest();

            Assert.areEqual(LoanStatusMachine.SUBMITTED, reload(loan.Id).Status__c);
            Credit_Check__c check = onlyCheck(loan.Id);
            Assert.areEqual(CreditScoringClient.FAILED, check.Status__c);
            Assert.isTrue(check.Error_Message__c.startsWith('Invalid response body'), check.Error_Message__c);
        }
    }

    @IsTest
    static void missingIncomeFailsWithoutCallout() {
        System.runAs(officer()) {
            CreditScoringCalloutMock mock = mockService();
            Loan_Application__c loan = submittedLoans(1, 100000)[0];
            loan.Monthly_Income__c = null;
            update loan;

            Test.startTest();
            sendToScoring(new List<Loan_Application__c>{ loan });
            Test.stopTest();

            Assert.areEqual(0, mock.requests.size(), 'No callout should be made without the required input');
            Assert.areEqual(LoanStatusMachine.SUBMITTED, reload(loan.Id).Status__c);
            Assert.areEqual(CreditScoringClient.FAILED, onlyCheck(loan.Id).Status__c);
        }
    }

    @IsTest
    static void sendsExpectedRequest() {
        System.runAs(officer()) {
            CreditScoringCalloutMock mock = mockService();
            Loan_Application__c loan = submittedLoans(1, 100000)[0];

            Test.startTest();
            sendToScoring(new List<Loan_Application__c>{ loan });
            Test.stopTest();

            Assert.areEqual(1, mock.requests.size());
            HttpRequest request = mock.requests[0];
            Assert.areEqual(CreditScoringClient.ENDPOINT, request.getEndpoint());
            Assert.areEqual('POST', request.getMethod());
            Assert.areEqual('application/json', request.getHeader('Content-Type'));

            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
            Assert.areEqual(String.valueOf(loan.Id), body.get('loanId'));
            Assert.isTrue(Decimal.valueOf(String.valueOf(body.get('amount'))) == 100000, 'amount: ' + body.get('amount'));
            Assert.areEqual('60', String.valueOf(body.get('termMonths')));
            Assert.areEqual('Personal', body.get('purpose'));
            Assert.areEqual(onlyCheck(loan.Id).Request_Id__c, body.get('requestId'),
                    'The credit check must record the requestId that was sent');
        }
    }

    @IsTest
    static void oneJobScoresAtMostOneBatch() {
        System.runAs(officer()) {
            CreditScoringCalloutMock mock = mockService();
            Integer total = CreditScoringJob.BATCH_SIZE + 5;
            List<Loan_Application__c> loans = submittedLoans(total, 100000);

            Test.startTest();
            sendToScoring(loans);
            Test.stopTest();

            // Chained jobs don't run in tests, so only the first batch is processed here
            Assert.areEqual(CreditScoringJob.BATCH_SIZE, mock.requests.size());
            Assert.areEqual(CreditScoringJob.BATCH_SIZE, [SELECT COUNT() FROM Credit_Check__c]);
            Assert.areEqual(5, [SELECT COUNT() FROM Loan_Application__c
            WHERE Status__c = :LoanStatusMachine.SCORING]);
        }
    }

    @IsTest
    static void onlyTransitionToScoringQueuesTheJob() {
        System.runAs(officer()) {
            mockService();
            Loan_Application__c loan = submittedLoans(1, 100000)[0];

            Test.startTest();
            loan.Amount__c = 110000;
            update loan;
            Assert.areEqual(0, Limits.getQueueableJobs(), 'A change other than status must not queue scoring');

            sendToScoring(new List<Loan_Application__c>{ loan });
            Assert.areEqual(1, Limits.getQueueableJobs());
            Test.stopTest();
        }
    }

}