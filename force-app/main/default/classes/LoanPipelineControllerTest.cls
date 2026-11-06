@IsTest
private class LoanPipelineControllerTest {
  private static final String OFFICER_USERNAME =
    'pipeline.officer.' +
    UserInfo.getOrganizationId() +
    '@test.example.com';

  @TestSetup
  static void setup() {
    User officer = new User(
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
      .Id,
      Username = OFFICER_USERNAME,
      LastName = 'Officer',
      FirstName = 'Pipeline',
      Email = 'pipeline.officer@test.example.com',
      Alias = 'pipeoff',
      TimeZoneSidKey = 'Asia/Jerusalem',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    insert officer;
    insert new PermissionSetAssignment(
      AssigneeId = officer.Id,
      PermissionSetId = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'Loan_Officer'
        LIMIT 1
      ]
      .Id
    );
  }

  private static User officer() {
    return [SELECT Id FROM User WHERE Username = :OFFICER_USERNAME LIMIT 1];
  }

  /** Inserts loans straight into a status, skipping the trigger, to set up a pipeline quickly. */
  private static void loans(
    String status,
    Integer count,
    Decimal amount,
    Decimal score
  ) {
    List<Loan_Application__c> records = new List<Loan_Application__c>();
    for (Integer i = 0; i < count; i++) {
      records.add(
        new Loan_Application__c(
          Status__c = status,
          Amount__c = amount,
          Term_Months__c = 60,
          Monthly_Income__c = 15000,
          Credit_Score__c = score,
          Risk_Tier__c = score == null ? null : 'B'
        )
      );
    }
    LoanApplicationTriggerHandler.bypassOn();
    insert records;
    LoanApplicationTriggerHandler.bypassOff();
  }

  private static LoanPipelineController.Stage stage(
    LoanPipelineController.Pipeline pipeline,
    String status
  ) {
    for (LoanPipelineController.Stage stage : pipeline.stages) {
      if (stage.status == status) {
        return stage;
      }
    }
    return null;
  }

  @IsTest
  static void summarisesThePipeline() {
    System.runAs(officer()) {
      loans(LoanStatusMachine.DRAFT, 2, 10000, null);
      loans(LoanStatusMachine.PENDING_APPROVAL, 3, 100000, 700);
      loans(LoanStatusMachine.APPROVED, 3, 50000, 760);
      loans(LoanStatusMachine.REJECTED, 1, 400000, 520);

      Test.startTest();
      LoanPipelineController.Pipeline pipeline = LoanPipelineController.getPipeline();
      Test.stopTest();

      Assert.areEqual(9, pipeline.totalCount);
      Assert.areEqual(
        8,
        pipeline.openCount,
        'Approved but not yet funded is still open'
      );
      Assert.areEqual(470000, pipeline.openAmount.intValue());
      Assert.areEqual(3, pipeline.pendingApprovalCount);
      Assert.areEqual(4, pipeline.decidedCount);
      Assert.areEqual(75, pipeline.approvalRate.intValue());
      // (3 * 700 + 3 * 760 + 520) / 7 = 700
      Assert.areEqual(700, pipeline.averageScore.intValue());
      Assert.areEqual(
        3,
        stage(pipeline, LoanStatusMachine.PENDING_APPROVAL).count
      );
      Assert.areEqual(
        300000,
        stage(pipeline, LoanStatusMachine.PENDING_APPROVAL).amount.intValue()
      );
      Assert.areEqual(9, pipeline.recent.size());
    }
  }

  @IsTest
  static void stagesFollowTheLifecycleOrder() {
    System.runAs(officer()) {
      Test.startTest();
      LoanPipelineController.Pipeline pipeline = LoanPipelineController.getPipeline();
      Test.stopTest();

      List<String> statuses = new List<String>();
      for (LoanPipelineController.Stage stage : pipeline.stages) {
        statuses.add(stage.status);
      }
      Assert.areEqual(LoanPipelineController.STAGE_ORDER, statuses);
      Assert.areEqual(
        'Pending Approval',
        stage(pipeline, LoanStatusMachine.PENDING_APPROVAL).label
      );
    }
  }

  @IsTest
  static void emptyPipelineHasNoRates() {
    System.runAs(officer()) {
      Test.startTest();
      LoanPipelineController.Pipeline pipeline = LoanPipelineController.getPipeline();
      Test.stopTest();

      Assert.areEqual(0, pipeline.totalCount);
      Assert.isNull(pipeline.approvalRate);
      Assert.isNull(pipeline.averageScore);
      Assert.isTrue(pipeline.recent.isEmpty());
    }
  }

  @IsTest
  static void recentRowsCarryDisplayLabels() {
    System.runAs(officer()) {
      loans(LoanStatusMachine.PENDING_APPROVAL, 1, 150000, 731);
      LoanApplicationTriggerHandler.allowCreditResultUpdates(true);
      Loan_Application__c loan = [SELECT Id FROM Loan_Application__c LIMIT 1];
      loan.Approval_Level__c = 'Branch_Manager';
      update loan;
      LoanApplicationTriggerHandler.allowCreditResultUpdates(false);

      Test.startTest();
      LoanPipelineController.LoanRow row = LoanPipelineController.getPipeline()
        .recent[0];
      Test.stopTest();

      Assert.areEqual('Pending Approval', row.statusLabel);
      Assert.areEqual('Branch Manager', row.approvalLevelLabel);
      Assert.areEqual(731, row.creditScore.intValue());
    }
  }
}
