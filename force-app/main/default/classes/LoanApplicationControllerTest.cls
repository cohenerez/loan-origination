@IsTest
private class LoanApplicationControllerTest {
  private static final String OFFICER_USERNAME =
    'ui.officer.' +
    UserInfo.getOrganizationId() +
    '@test.example.com';

  @TestSetup
  static void setup() {
    User officer = new User(
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
      .Id,
      Username = OFFICER_USERNAME,
      LastName = 'Officer',
      FirstName = 'Screen',
      Email = 'ui.officer@test.example.com',
      Alias = 'uioffcr',
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
    System.runAs(officer) {
      insert new Contact(
        FirstName = 'Dana',
        LastName = 'Levi',
        Email = 'dana.levi@example.com'
      );
    }
  }

  private static User officer() {
    return [SELECT Id FROM User WHERE Username = :OFFICER_USERNAME LIMIT 1];
  }

  private static Loan_Application__c newLoan() {
    Loan_Application__c loan = new Loan_Application__c(
      Applicant__c = [SELECT Id FROM Contact LIMIT 1]
      .Id,
      Amount__c = 150000,
      Term_Months__c = 60,
      Monthly_Income__c = 15000,
      Purpose__c = 'Personal'
    );
    insert loan;
    return loan;
  }

  /** Pending Approval with credit results, as the scoring job leaves it. */
  private static Loan_Application__c pendingApprovalLoan() {
    Test.setMock(System.HttpCalloutMock.class, new CreditScoringCalloutMock());
    Loan_Application__c loan = newLoan();
    update new Loan_Application__c(
      Id = loan.Id,
      Status__c = LoanStatusMachine.SUBMITTED
    );
    update new Loan_Application__c(
      Id = loan.Id,
      Status__c = LoanStatusMachine.SCORING
    );
    LoanApplicationTriggerHandler.allowCreditResultUpdates(true);
    update new Loan_Application__c(
      Id = loan.Id,
      Status__c = LoanStatusMachine.PENDING_APPROVAL,
      Credit_Score__c = 731,
      Risk_Tier__c = 'B',
      Approval_Level__c = 'Branch_Manager'
    );
    LoanApplicationTriggerHandler.allowCreditResultUpdates(false);
    return loan;
  }

  private static List<String> targets(
    List<LoanApplicationController.LoanAction> actions
  ) {
    List<String> result = new List<String>();
    for (LoanApplicationController.LoanAction action : actions) {
      result.add(action.targetStatus);
    }
    return result;
  }

  @IsTest
  static void draftViewHasDetailsAndSubmitAction() {
    System.runAs(officer()) {
      Loan_Application__c loan = newLoan();

      Test.startTest();
      LoanApplicationController.LoanView view = LoanApplicationController.getLoanView(
        loan.Id
      );
      Test.stopTest();

      Assert.areEqual(LoanStatusMachine.DRAFT, view.status);
      Assert.areEqual('Dana Levi', view.applicantName);
      Assert.areEqual(150000, view.amount.intValue());
      Assert.isNull(view.creditScore);
      Assert.areEqual(
        new List<String>{ LoanStatusMachine.SUBMITTED },
        targets(view.actions)
      );
      Assert.areEqual('Submit application', view.actions[0].label);
      Assert.isTrue(view.creditChecks.isEmpty());
    }
  }

  @IsTest
  static void pendingApprovalOffersDecisionActions() {
    System.runAs(officer()) {
      Loan_Application__c loan;
      LoanApplicationController.LoanView view;

      Test.startTest();
      loan = pendingApprovalLoan();
      view = LoanApplicationController.getLoanView(loan.Id);
      Test.stopTest();

      Assert.areEqual('Pending Approval', view.statusLabel);
      Assert.areEqual('Branch Manager', view.approvalLevelLabel);
      Assert.areEqual(731, view.creditScore.intValue());
      // Ranked: Approve, Reject, Return for changes
      Assert.areEqual(
        new List<String>{
          LoanStatusMachine.APPROVED,
          LoanStatusMachine.REJECTED,
          LoanStatusMachine.SUBMITTED
        },
        targets(view.actions)
      );
      Assert.isTrue(
        view.actions[1].requiresReason,
        'Reject must ask for a reason'
      );
      Assert.areEqual('Return for changes', view.actions[2].label);
    }
  }

  @IsTest
  static void scoringHasNoUserActions() {
    Assert.isTrue(
      LoanApplicationController.actionsFor(LoanStatusMachine.SCORING).isEmpty()
    );
    Assert.isTrue(
      LoanApplicationController.actionsFor(LoanStatusMachine.FUNDED).isEmpty()
    );
    Assert.isTrue(
      LoanApplicationController.actionsFor(LoanStatusMachine.REJECTED).isEmpty()
    );
  }

  @IsTest
  static void viewIncludesScoringHistory() {
    System.runAs(officer()) {
      Loan_Application__c loan = newLoan();
      insert new List<Credit_Check__c>{
        new Credit_Check__c(
          Loan_Application__c = loan.Id,
          Request_Id__c = 'req-a',
          Status__c = 'Failed',
          Error_Message__c = 'HTTP 503 Service Unavailable'
        ),
        new Credit_Check__c(
          Loan_Application__c = loan.Id,
          Request_Id__c = 'req-b',
          Status__c = 'Success',
          Score__c = 731,
          Response_Time_Ms__c = 420
        )
      };

      Test.startTest();
      LoanApplicationController.LoanView view = LoanApplicationController.getLoanView(
        loan.Id
      );
      Test.stopTest();

      Assert.areEqual(2, view.creditChecks.size());
      Set<String> requestIds = new Set<String>{
        view.creditChecks[0].requestId,
        view.creditChecks[1].requestId
      };
      Assert.isTrue(
        requestIds.contains('req-a') && requestIds.contains('req-b')
      );
    }
  }

  @IsTest
  static void submitChangesStatus() {
    System.runAs(officer()) {
      Loan_Application__c loan = newLoan();

      Test.startTest();
      LoanApplicationController.changeStatus(
        loan.Id,
        LoanStatusMachine.SUBMITTED,
        null
      );
      Test.stopTest();

      Assert.areEqual(
        LoanStatusMachine.SUBMITTED,
        [SELECT Status__c FROM Loan_Application__c WHERE Id = :loan.Id]
        .Status__c
      );
    }
  }

  @IsTest
  static void rejectWithReasonIsSaved() {
    System.runAs(officer()) {
      Loan_Application__c loan;

      Test.startTest();
      loan = pendingApprovalLoan();
      LoanApplicationController.changeStatus(
        loan.Id,
        LoanStatusMachine.REJECTED,
        '  Income could not be verified  '
      );
      Test.stopTest();

      Loan_Application__c saved = [
        SELECT Status__c, Decision_Reason__c
        FROM Loan_Application__c
        WHERE Id = :loan.Id
      ];
      Assert.areEqual(LoanStatusMachine.REJECTED, saved.Status__c);
      Assert.areEqual('Income could not be verified', saved.Decision_Reason__c);
    }
  }

  @IsTest
  static void rejectWithoutReasonIsRefused() {
    System.runAs(officer()) {
      Loan_Application__c loan;
      String message;

      Test.startTest();
      loan = pendingApprovalLoan();
      try {
        LoanApplicationController.changeStatus(
          loan.Id,
          LoanStatusMachine.REJECTED,
          '   '
        );
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
      Test.stopTest();

      Assert.areEqual('Please enter a reason.', message);
    }
  }

  @IsTest
  static void systemTransitionsAreRefused() {
    System.runAs(officer()) {
      Loan_Application__c loan = newLoan();
      String message;

      Test.startTest();
      try {
        // Draft -> Approved isn't a valid transition at all
        LoanApplicationController.changeStatus(
          loan.Id,
          LoanStatusMachine.APPROVED,
          null
        );
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
      Test.stopTest();

      Assert.isTrue(
        message.contains('isn\'t available while the application is Draft'),
        message
      );
    }
  }

  @IsTest
  static void triggerErrorsAreShownToTheUser() {
    System.runAs(officer()) {
      Loan_Application__c loan = newLoan();
      String message;

      Test.startTest();
      // A credit score typed by hand is rejected by the trigger with a readable message,
      // which changeStatus passes on to the screen via getDmlMessage
      try {
        update new Loan_Application__c(Id = loan.Id, Credit_Score__c = 800);
      } catch (DmlException e) {
        message = e.getDmlMessage(0);
      }
      Test.stopTest();

      Assert.isTrue(
        message.contains('set by the credit scoring service'),
        message
      );
    }
  }

  @IsTest
  static void unknownRecordGivesReadableError() {
    System.runAs(officer()) {
      Loan_Application__c loan = newLoan();
      Id loanId = loan.Id;
      delete loan;
      String message;

      Test.startTest();
      try {
        LoanApplicationController.getLoanView(loanId);
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
      Test.stopTest();

      Assert.areEqual('Loan application not found or not accessible.', message);
    }
  }
}
