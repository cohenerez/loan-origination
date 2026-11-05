
@IsTest
private  class LoanApprovalRouterTest {

    private static void useTestThresholds() {
        LoanApprovalRouter.thresholdsOverride = new List<Approval_Threshold__mdt>{
                new Approval_Threshold__mdt(Max_Amount__c = 2000000, Min_Score__c = 580, Approver_Level__c = 'Credit_Committee', Sort_Order__c = 3),
                new Approval_Threshold__mdt(Max_Amount__c = 50000, Min_Score__c = 700,   Approver_Level__c = 'Auto', Sort_Order__c = 1),
                new Approval_Threshold__mdt(Max_Amount__c = 250000, Min_Score__c = 620,Approver_Level__c = 'Branch_Manager', Sort_Order__c = 2)
        };
    }

    @IsTest
    static void smallLoanWithHighScoreIsAutoApproved() {
        useTestThresholds();
        LoanApprovalRouter.Decision decision = new LoanApprovalRouter().route(30000, 760);
        Assert.isTrue(decision.autoApprove);
        Assert.areEqual(LoanStatusMachine.APPROVED, decision.status);
        Assert.areEqual('Auto', decision.approvalLevel);
        Assert.isTrue(decision.reason.startsWith('Auto-approved'), decision.reason);
    }

    @IsTest
    static void smallLoanWithMediumScoreEscalatesToBranchManager() {
        useTestThresholds();
        LoanApprovalRouter.Decision decision = new LoanApprovalRouter().route(30000, 650);
        Assert.isFalse(decision.autoApprove);
        Assert.areEqual(LoanStatusMachine.PENDING_APPROVAL, decision.status);
        Assert.areEqual('Branch_Manager', decision.approvalLevel);
    }

    @IsTest
    static void largeLoanGoesToCreditCommittee() {
        useTestThresholds();
        LoanApprovalRouter.Decision decision = new LoanApprovalRouter().route(1000000, 600);
        Assert.areEqual(LoanStatusMachine.PENDING_APPROVAL, decision.status);
        Assert.areEqual('Credit_Committee', decision.approvalLevel);
    }

    @IsTest
    static void scoreBelowEveryThresholdIsRejected() {
        useTestThresholds();
        LoanApprovalRouter.Decision decision = new LoanApprovalRouter().route(100000, 550);
        Assert.areEqual(LoanStatusMachine.REJECTED, decision.status);
        Assert.isNull(decision.approvalLevel);
        Assert.isTrue(decision.reason.startsWith('Automatically rejected'), decision.reason);
    }

    @IsTest
    static void amountAboveEveryThresholdIsRejected() {
        useTestThresholds();
        LoanApprovalRouter.Decision decision = new LoanApprovalRouter().route(5000000, 820);
        Assert.areEqual(LoanStatusMachine.REJECTED, decision.status);
    }

    @IsTest
    static void deployedThresholdsAreLoaded() {
         LoanApprovalRouter.Decision decision = new LoanApprovalRouter().route(1000, 849);
        Assert.areNotEqual(LoanStatusMachine.REJECTED, decision.status, 'A tiny loan with a near-perfect score should match a deployed threshold');

    }




}