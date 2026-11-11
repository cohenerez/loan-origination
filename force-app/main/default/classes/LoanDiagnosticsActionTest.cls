@IsTest
private class LoanDiagnosticsActionTest {
  private static final Datetime NOW = Datetime.newInstanceGmt(
    2026,
    11,
    11,
    12,
    0,
    0
  );

  /** Builds an in-memory loan, including read-only fields (Name, LastModifiedDate) and its last credit check. */
  private static Loan_Application__c loan(
    String status,
    Integer minutesAgo,
    Map<String, Object> fields,
    Map<String, Object> lastCheck
  ) {
    Map<String, Object> values = new Map<String, Object>{
      'attributes' => new Map<String, Object>{
        'type' => 'Loan_Application__c'
      },
      'Name' => 'LA-000042',
      'Status__c' => status,
      'Amount__c' => 30000,
      'Monthly_Income__c' => 15000,
      'Applicant__c' => '003000000000001',
      'Applicant__r' => new Map<String, Object>{
        'attributes' => new Map<String, Object>{ 'type' => 'Contact' },
        'Email' => 'dana@example.com'
      },
      'LastModifiedDate' => NOW.addMinutes(-minutesAgo)
    };
    if (fields != null) {
      values.putAll(fields);
    }
    if (lastCheck != null) {
      lastCheck.put(
        'attributes',
        new Map<String, Object>{ 'type' => 'Credit_Check__c' }
      );
      values.put(
        'Credit_Checks__r',
        new Map<String, Object>{
          'totalSize' => 1,
          'done' => true,
          'records' => new List<Object>{ lastCheck }
        }
      );
    }
    return (Loan_Application__c) JSON.deserialize(
      JSON.serialize(values),
      Loan_Application__c.class
    );
  }

  private static Map<String, Object> failedCheck(
    String status,
    String error,
    Integer minutesAgo
  ) {
    return new Map<String, Object>{
      'Status__c' => status,
      'Error_Message__c' => error,
      'CreatedDate' => NOW.addMinutes(-minutesAgo)
    };
  }

  private static CreditScoringHealthCheck.Status health(
    Boolean up,
    String error
  ) {
    CreditScoringHealthCheck.Status status = new CreditScoringHealthCheck.Status();
    status.up = up;
    status.errorMessage = error;
    return status;
  }

  @IsTest
  static void draftWithoutIncomeExplainsWhatIsMissing() {
    LoanDiagnosticsAction.Result result = LoanDiagnosticsAction.diagnose(
      loan(
        'Draft',
        30,
        new Map<String, Object>{ 'Monthly_Income__c' => null },
        null
      ),
      NOW,
      null
    );

    Assert.isTrue(result.found);
    Assert.isFalse(
      result.stuck,
      'A draft waits for the officer, it is not stuck'
    );
    Assert.isTrue(
      result.blockers.contains('Monthly income is missing'),
      result.blockers
    );
    Assert.isTrue(
      result.nextStep.contains('complete the missing details'),
      result.nextStep
    );
  }

  @IsTest
  static void completeDraftIsReadyToSubmit() {
    LoanDiagnosticsAction.Result result = LoanDiagnosticsAction.diagnose(
      loan('Draft', 30, null, null),
      NOW,
      null
    );

    Assert.areEqual('', result.blockers);
    Assert.areEqual(
      'The loan officer should click Submit application.',
      result.nextStep
    );
  }

  @IsTest
  static void applicantWithoutEmailIsFlagged() {
    Map<String, Object> noEmail = new Map<String, Object>{
      'Applicant__r' => new Map<String, Object>{
        'attributes' => new Map<String, Object>{ 'type' => 'Contact' },
        'Email' => null
      }
    };
    LoanDiagnosticsAction.Result result = LoanDiagnosticsAction.diagnose(
      loan('Draft', 5, noEmail, null),
      NOW,
      null
    );

    Assert.isTrue(
      result.blockers.contains('no email address'),
      result.blockers
    );
  }

  @IsTest
  static void rejectedApiKeyIsExplained() {
    Loan_Application__c submitted = loan(
      'Submitted',
      20,
      null,
      failedCheck('Failed', 'HTTP 401 Unauthorized', 20)
    );

    LoanDiagnosticsAction.Result result = LoanDiagnosticsAction.diagnose(
      submitted,
      NOW,
      health(true, null)
    );

    Assert.isTrue(result.stuck);
    Assert.isTrue(
      result.summary.startsWith('Credit scoring failed 20 minutes ago'),
      result.summary
    );
    Assert.isTrue(
      result.blockers.contains('HTTP 401 Unauthorized'),
      result.blockers
    );
    Assert.isTrue(result.blockers.contains('ApiKey'), result.blockers);
    Assert.isTrue(
      result.nextStep.contains('Run credit scoring'),
      result.nextStep
    );
  }

  @IsTest
  static void serviceDownIsReportedForAFailedScoring() {
    Loan_Application__c submitted = loan(
      'Submitted',
      5,
      null,
      failedCheck('Failed', 'HTTP 503', 5)
    );

    LoanDiagnosticsAction.Result result = LoanDiagnosticsAction.diagnose(
      submitted,
      NOW,
      health(false, 'Read timed out')
    );

    Assert.isTrue(
      result.blockers.contains('not responding right now: Read timed out'),
      result.blockers
    );
  }

  @IsTest
  static void timeoutWithServiceBackUpSuggestsRetry() {
    Loan_Application__c submitted = loan(
      'Submitted',
      5,
      null,
      failedCheck('Timeout', 'Read timed out', 5)
    );

    LoanDiagnosticsAction.Result result = LoanDiagnosticsAction.diagnose(
      submitted,
      NOW,
      health(true, null)
    );

    Assert.isTrue(
      result.blockers.contains('a retry should work'),
      result.blockers
    );
  }

  @IsTest
  static void submittedForADayWithoutScoringIsStuck() {
    LoanDiagnosticsAction.Result fresh = LoanDiagnosticsAction.diagnose(
      loan('Submitted', 60, null, null),
      NOW,
      null
    );
    LoanDiagnosticsAction.Result old = LoanDiagnosticsAction.diagnose(
      loan('Submitted', 2 * 24 * 60, null, null),
      NOW,
      null
    );

    Assert.isFalse(fresh.stuck);
    Assert.isTrue(old.stuck);
    Assert.isTrue(old.summary.contains('2 days'), old.summary);
  }

  @IsTest
  static void scoringIsOnlyStuckWhenItTakesTooLong() {
    LoanDiagnosticsAction.Result running = LoanDiagnosticsAction.diagnose(
      loan('Scoring', 1, null, null),
      NOW,
      null
    );
    LoanDiagnosticsAction.Result hanging = LoanDiagnosticsAction.diagnose(
      loan('Scoring', 45, null, null),
      NOW,
      health(false, 'Connection refused')
    );

    Assert.isFalse(running.stuck);
    Assert.isTrue(hanging.stuck);
    Assert.isTrue(
      hanging.blockers.contains('Connection refused'),
      hanging.blockers
    );
    Assert.isTrue(hanging.nextStep.contains('Apex Jobs'), hanging.nextStep);
  }

  @IsTest
  static void pendingApprovalNamesTheApproverAndUnverifiedDocuments() {
    Map<String, Object> fields = new Map<String, Object>{
      'Approval_Level__c' => 'Credit_Committee',
      'Credit_Score__c' => 640,
      'Total_Documents__c' => 3,
      'Verified_Documents__c' => 1
    };
    LoanDiagnosticsAction.Result result = LoanDiagnosticsAction.diagnose(
      loan('Pending_Approval', 3 * 24 * 60, fields, null),
      NOW,
      null
    );

    Assert.isTrue(
      result.stuck,
      'Three days without a decision is past the approval target'
    );
    Assert.isTrue(result.summary.contains('Credit Committee'), result.summary);
    Assert.isTrue(
      result.blockers.contains('2 of 3 documents are not verified'),
      result.blockers
    );
    Assert.isTrue(
      result.nextStep.startsWith('The Credit Committee should'),
      result.nextStep
    );
  }

  @IsTest
  static void finalStatusesAreNotStuck() {
    LoanDiagnosticsAction.Result funded = LoanDiagnosticsAction.diagnose(
      loan('Funded', 10000, null, null),
      NOW,
      null
    );
    LoanDiagnosticsAction.Result rejected = LoanDiagnosticsAction.diagnose(
      loan(
        'Rejected',
        10000,
        new Map<String, Object>{
          'Decision_Reason__c' => 'Score below minimum'
        },
        null
      ),
      NOW,
      null
    );

    Assert.isFalse(funded.stuck);
    Assert.isFalse(rejected.stuck);
    Assert.isTrue(
      rejected.summary.contains('Score below minimum'),
      rejected.summary
    );
  }

  @IsTest
  static void durationsReadNaturally() {
    Assert.areEqual('a minute', LoanDiagnosticsAction.describeDuration(0));
    Assert.areEqual('45 minutes', LoanDiagnosticsAction.describeDuration(45));
    Assert.areEqual('5 hours', LoanDiagnosticsAction.describeDuration(300));
    Assert.areEqual(
      '3 days',
      LoanDiagnosticsAction.describeDuration(3 * 24 * 60)
    );
  }

  @IsTest
  static void referencesAreParsed() {
    Assert.isNull(LoanDiagnosticsAction.toId('LA-000042'));
    Assert.isNull(LoanDiagnosticsAction.toId('not-an-id-at-all'));
    Assert.isNotNull(LoanDiagnosticsAction.toId('003000000000001'));
  }

  // ---- The invocable method end to end: query, health check callout, result ----

  private class HealthMock implements System.HttpCalloutMock {
    public Integer calls = 0;
    public HttpResponse respond(HttpRequest request) {
      calls++;
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody('{"status":"UP"}');
      return response;
    }
  }

  private static Loan_Application__c insertLoan(String status) {
    Contact applicant = new Contact(
      LastName = 'Levi',
      Email = 'dana.levi@example.com'
    );
    insert applicant;
    Loan_Application__c record = new Loan_Application__c(
      Applicant__c = applicant.Id,
      Amount__c = 30000,
      Term_Months__c = 60,
      Monthly_Income__c = 15000,
      Status__c = status
    );
    insert record;
    return [SELECT Id, Name FROM Loan_Application__c WHERE Id = :record.Id];
  }

  private static LoanDiagnosticsAction.Result run(String reference) {
    LoanDiagnosticsAction.Request request = new LoanDiagnosticsAction.Request();
    request.loanReference = reference;
    return LoanDiagnosticsAction.diagnose(
      new List<LoanDiagnosticsAction.Request>{ request }
    )[0];
  }

  @IsTest
  static void findsTheLoanByNumberInAnyCase() {
    Loan_Application__c record = insertLoan('Draft');

    Test.startTest();
    LoanDiagnosticsAction.Result result = run(
      '  ' + record.Name.toLowerCase() + ' '
    );
    Test.stopTest();

    Assert.isTrue(result.found);
    Assert.areEqual(record.Name, result.loanName);
    Assert.areEqual('Draft', result.status);
  }

  @IsTest
  static void failedScoringTriggersOneLiveHealthCheck() {
    Loan_Application__c record = insertLoan('Submitted');
    insert new Credit_Check__c(
      Loan_Application__c = record.Id,
      Status__c = 'Failed',
      Error_Message__c = 'HTTP 401 Unauthorized',
      Request_Id__c = 'test-request-1'
    );
    HealthMock mock = new HealthMock();
    Test.setMock(System.HttpCalloutMock.class, mock);

    Test.startTest();
    LoanDiagnosticsAction.Result result = run(record.Id);
    Test.stopTest();

    Assert.areEqual(1, mock.calls);
    Assert.isTrue(result.stuck);
    Assert.isTrue(result.blockers.contains('ApiKey'), result.blockers);
  }

  @IsTest
  static void unknownReferenceIsReported() {
    LoanDiagnosticsAction.Result result = run('LA-999999');

    Assert.isFalse(result.found);
    Assert.isTrue(result.summary.contains('LA-999999'), result.summary);
  }
}
