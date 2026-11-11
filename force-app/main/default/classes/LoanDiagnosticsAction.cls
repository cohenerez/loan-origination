public with sharing class LoanDiagnosticsAction {
  /** How long an application may wait at each human step before it counts as stuck. */
  @TestVisible
  static final Integer SCORING_MINUTES = 10;
  @TestVisible
  static final Integer SUBMITTED_HOURS = 24;
  @TestVisible
  static final Integer APPROVAL_HOURS = 48;
  @TestVisible
  static final Integer FUNDING_HOURS = 72;

  public class Request {
    @InvocableVariable(
      label='Loan application'
      description='The loan application number, for example LA-000012, or its record Id.'
      required=true
    )
    public String loanReference;
  }

  public class Result {
    @InvocableVariable(
      label='Found'
      description='False when no loan application matches the reference.'
    )
    public Boolean found = false;
    @InvocableVariable(label='Loan number')
    public String loanName;
    @InvocableVariable(label='Status')
    public String status;
    @InvocableVariable(
      label='Stuck'
      description='True when the application is not moving and someone must act.'
    )
    public Boolean stuck = false;
    @InvocableVariable(
      label='Summary'
      description='One-sentence diagnosis to lead the answer with.'
    )
    public String summary;
    @InvocableVariable(
      label='Blockers'
      description='What keeps the application from moving on, one per line.'
    )
    public String blockers;
    @InvocableVariable(label='Next step' description='Who should do what next.')
    public String nextStep;
    @InvocableVariable(
      label='Last updated'
      description='When the application last changed.'
    )
    public Datetime lastUpdated;
  }

  @InvocableMethod(
    label='Diagnose Loan Application'
    description='Explains the current status of a loan application, why it may be stuck or delayed, and the next step. Use it when a user asks why an application is stuck, slow, not moving, or what is happening with it.'
    category='Loan Origination'
  )
  public static List<Result> diagnose(List<Request> requests) {
    List<Result> results = new List<Result>();
    CreditScoringHealthCheck.Status health;
    for (Request request : requests) {
      Loan_Application__c loan = find(request.loanReference);
      if (loan == null) {
        Result notFound = new Result();
        notFound.summary =
          'No loan application matches "' +
          request.loanReference +
          '".';
        results.add(notFound);
        continue;
      }

      if (health == null && needsHealthCheck(loan)) {
        health = CreditScoringHealthCheck.check();
      }
      results.add(diagnose(loan, Datetime.now(), health));
    }
    return results;
  }

  private static Loan_Application__c find(String reference) {
    if (String.isBlank(reference)) {
      return null;
    }
    String value = reference.trim();
    Id loanId = toId(value);
    List<Loan_Application__c> loans = loanId != null
      ? query(loanId, null)
      : query(null, value.toUpperCase());
    return loans.isEmpty() ? null : loans[0];
  }

  @TestVisible
  static Id toId(String value) {
    if ((value.length() != 15 && value.length() != 18) || value.contains('-')) {
      return null;
    }
    try {
      return Id.valueOf(value);
    } catch (StringException notAnId) {
      return null;
    }
  }

  private static List<Loan_Application__c> query(Id loanId, String name) {
    return [
      SELECT
        Id,
        Name,
        Status__c,
        Amount__c,
        Monthly_Income__c,
        Applicant__c,
        Applicant__r.Email,
        Approval_Level__c,
        Credit_Score__c,
        Decision_Reason__c,
        Submitted_Date__c,
        Total_Documents__c,
        Verified_Documents__c,
        LastModifiedDate,
        (
          SELECT Status__c, Error_Message__c, CreatedDate
          FROM Credit_Checks__r
          ORDER BY CreatedDate DESC
          LIMIT 1
        )
      FROM Loan_Application__c
      WHERE Id = :loanId OR Name = :name
      WITH USER_MODE
      LIMIT 1
    ];
  }

  @TestVisible
  static Boolean needsHealthCheck(Loan_Application__c loan) {
    return loan.Status__c == LoanStatusMachine.SCORING || lastCheckFailed(loan);
  }

  @TestVisible
  static Result diagnose(
    Loan_Application__c loan,
    Datetime now,
    CreditScoringHealthCheck.Status health
  ) {
    Result result = new Result();
    result.found = true;
    result.loanName = loan.Name;
    result.status = loan.Status__c;
    result.lastUpdated = loan.LastModifiedDate;

    List<String> blockers = new List<String>();
    Integer minutesSince = minutesBetween(loan.LastModifiedDate, now);
    String waited = describeDuration(minutesSince);

    switch on loan.Status__c {
      when 'Draft' {
        blockers.addAll(missingDetails(loan));
        result.summary = blockers.isEmpty()
          ? 'The application is a draft and has not been submitted yet.'
          : 'The application is a draft and is missing details it needs before it can be submitted.';
        result.nextStep = blockers.isEmpty()
          ? 'The loan officer should click Submit application.'
          : 'The loan officer should complete the missing details, then click Submit application.';
      }
      when 'Submitted' {
        blockers.addAll(missingDetails(loan));
        if (lastCheckFailed(loan)) {
          Credit_Check__c check = loan.Credit_Checks__r[0];
          result.stuck = true;
          result.summary =
            'Credit scoring failed ' +
            describeDuration(minutesBetween(check.CreatedDate, now)) +
            ' ago, so the application went back to Submitted.';
          blockers.add(
            'Last scoring attempt: ' +
              check.Status__c +
              (String.isBlank(check.Error_Message__c)
                ? ''
                : ' (' + check.Error_Message__c + ')')
          );
          blockers.add(explainFailure(check, health));
          result.nextStep = 'Fix the cause above, then the loan officer should click Run credit scoring to retry.';
        } else {
          result.stuck = minutesSince >= SUBMITTED_HOURS * 60;
          result.summary =
            'The application was submitted ' +
            waited +
            ' ago and is waiting for credit scoring to be started.';
          result.nextStep = 'The loan officer should click Run credit scoring.';
        }
      }
      when 'Scoring' {
        if (minutesSince < SCORING_MINUTES) {
          result.summary = 'Credit scoring is running right now; it usually finishes within seconds.';
          result.nextStep = 'No action needed. Check again in a minute.';
        } else {
          result.stuck = true;
          result.summary =
            'Credit scoring started ' +
            waited +
            ' ago and no result came back.';
          blockers.add('The background scoring job did not finish.');
          if (health != null && health.up != true) {
            blockers.add(
              'The scoring service is not responding right now' +
              (String.isBlank(health.errorMessage)
                ? '.'
                : ': ' + health.errorMessage)
            );
          }
          result.nextStep =
            'An administrator should check CreditScoringJob in Setup > Apex Jobs' +
            ' and the scoring service, then move the application back to Submitted to retry.';
        }
      }
      when 'Pending_Approval' {
        String approver = approverLabel(loan.Approval_Level__c);
        result.stuck = minutesSince >= APPROVAL_HOURS * 60;
        result.summary =
          'The application passed credit scoring (score ' +
          loan.Credit_Score__c +
          ') and has been waiting for the ' +
          approver +
          ' for ' +
          waited +
          '.';
        blockers.add('Needs a decision from the ' + approver + '.');
        Integer unverified = unverifiedDocuments(loan);
        if (unverified > 0) {
          blockers.add(
            unverified +
              ' of ' +
              loan.Total_Documents__c.intValue() +
              ' documents are not verified yet.'
          );
        }
        result.nextStep =
          'The ' +
          approver +
          ' should approve or reject the application.';
      }
      when 'Approved' {
        result.stuck = minutesSince >= FUNDING_HOURS * 60;
        result.summary =
          'The application was approved and has been waiting to be funded for ' +
          waited +
          '.';
        result.nextStep = 'Operations should release the funds and mark the loan as funded.';
      }
      when 'Funded' {
        result.summary = 'The loan is funded and the application is closed.';
        result.nextStep = 'No action needed.';
      }
      when 'Rejected' {
        result.summary =
          'The application was rejected' +
          (String.isBlank(loan.Decision_Reason__c)
            ? '.'
            : ': ' + loan.Decision_Reason__c);
        result.nextStep = 'No action needed. A new application is required to apply again.';
      }
      when else {
        result.summary =
          'The application has an unknown status: ' +
          loan.Status__c +
          '.';
        result.nextStep = 'An administrator should check the record.';
      }
    }

    result.blockers = String.join(blockers, '\n');
    return result;
  }

  private static List<String> missingDetails(Loan_Application__c loan) {
    List<String> missing = new List<String>();
    if (loan.Amount__c == null) {
      missing.add('The requested amount is missing.');
    }
    if (loan.Monthly_Income__c == null) {
      missing.add('Monthly income is missing, so credit scoring cannot run.');
    }
    if (loan.Applicant__c == null) {
      missing.add('No applicant is linked to the application.');
    } else if (
      loan.Applicant__r == null || String.isBlank(loan.Applicant__r.Email)
    ) {
      missing.add(
        'The applicant has no email address, so they will not receive status updates.'
      );
    }
    return missing;
  }

  private static Boolean lastCheckFailed(Loan_Application__c loan) {
    List<Credit_Check__c> checks = loan.Credit_Checks__r;
    return checks != null &&
      !checks.isEmpty() &&
      checks[0].Status__c != 'Success';
  }

  @TestVisible
  static String explainFailure(
    Credit_Check__c check,
    CreditScoringHealthCheck.Status health
  ) {
    String error = check.Error_Message__c == null ? '' : check.Error_Message__c;
    if (error.contains('401') || error.contains('403')) {
      return 'The scoring service rejected the API key: the ApiKey value of the Credit_Scoring external' +
        ' credential does not match the service.';
    }
    if (health != null && health.up != true) {
      return 'The scoring service is not responding right now' +
        (String.isBlank(health.errorMessage)
          ? '.'
          : ': ' + health.errorMessage);
    }
    if (check.Status__c == 'Timeout') {
      return 'The scoring service did not answer in time; it is responding now, so a retry should work.';
    }
    if (health != null && health.up == true) {
      return 'The scoring service is responding now, so the failure was probably temporary and a retry should work.';
    }
    return 'The scoring service returned an error.';
  }

  private static String approverLabel(String approvalLevel) {
    if (approvalLevel == 'Credit_Committee') {
      return 'Credit Committee';
    }
    if (approvalLevel == 'Branch_Manager') {
      return 'Branch Manager';
    }
    return 'approver';
  }

  private static Integer unverifiedDocuments(Loan_Application__c loan) {
    Decimal total = loan.Total_Documents__c == null
      ? 0
      : loan.Total_Documents__c;
    Decimal verified = loan.Verified_Documents__c == null
      ? 0
      : loan.Verified_Documents__c;
    return Math.max(0, (total - verified).intValue());
  }

  private static Integer minutesBetween(Datetime fromTime, Datetime toTime) {
    if (fromTime == null || toTime == null) {
      return 0;
    }
    return ((toTime.getTime() - fromTime.getTime()) / 60000).intValue();
  }

  @TestVisible
  static String describeDuration(Integer minutes) {
    if (minutes < 2) {
      return 'a minute';
    }
    if (minutes < 120) {
      return minutes + ' minutes';
    }
    Integer hours = minutes / 60;
    if (hours < 48) {
      return hours + ' hours';
    }
    return (hours / 24) + ' days';
  }
}
