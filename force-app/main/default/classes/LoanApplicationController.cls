/**
 * Backend for the loanCommandCenter Lightning Web Component.
 * Returns one view model per application (details, credit results, scoring history and the
 * actions the current user may take) and performs status changes through the state machine.
 */
public with sharing class LoanApplicationController {
  public class LoanAction {
    @AuraEnabled
    public String targetStatus;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String style;
    @AuraEnabled
    public String iconName;
    @AuraEnabled
    public Boolean requiresReason = false;
    Integer rank;
  }

  public class CreditCheckView {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Decimal score;
    @AuraEnabled
    public Decimal responseTimeMs;
    @AuraEnabled
    public String errorMessage;
    @AuraEnabled
    public Datetime createdDate;
    @AuraEnabled
    public String requestId;
  }

  public class LoanView {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String statusLabel;
    @AuraEnabled
    public String applicantName;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Decimal termMonths;
    @AuraEnabled
    public Decimal monthlyIncome;
    @AuraEnabled
    public Decimal loanToIncome;
    @AuraEnabled
    public String purpose;
    @AuraEnabled
    public Decimal creditScore;
    @AuraEnabled
    public String riskTier;
    @AuraEnabled
    public String approvalLevel;
    @AuraEnabled
    public String approvalLevelLabel;
    @AuraEnabled
    public String decisionReason;
    @AuraEnabled
    public Datetime submittedDate;
    @AuraEnabled
    public Datetime decisionDate;
    @AuraEnabled
    public List<LoanAction> actions;
    @AuraEnabled
    public List<CreditCheckView> creditChecks;
  }

  @AuraEnabled(cacheable=true)
  public static LoanView getLoanView(Id loanId) {
    List<Loan_Application__c> loans = [
      SELECT
        Id,
        Name,
        Status__c,
        Applicant__r.Name,
        Amount__c,
        Term_Months__c,
        Monthly_Income__c,
        Loan_To_Income_Ratio__c,
        Purpose__c,
        Credit_Score__c,
        Risk_Tier__c,
        Approval_Level__c,
        Decision_Reason__c,
        Submitted_Date__c,
        Decision_Date__c
      FROM Loan_Application__c
      WHERE Id = :loanId
      WITH USER_MODE
    ];
    if (loans.isEmpty()) {
      throw auraError('Loan application not found or not accessible.');
    }
    Loan_Application__c loan = loans[0];

    LoanView view = new LoanView();
    view.id = loan.Id;
    view.name = loan.Name;
    view.status = loan.Status__c;
    view.statusLabel = label(loan.Status__c);
    view.applicantName = loan.Applicant__r?.Name;
    view.amount = loan.Amount__c;
    view.termMonths = loan.Term_Months__c;
    view.monthlyIncome = loan.Monthly_Income__c;
    view.loanToIncome = loan.Loan_To_Income_Ratio__c;
    view.purpose = loan.Purpose__c;
    view.creditScore = loan.Credit_Score__c;
    view.riskTier = loan.Risk_Tier__c;
    view.approvalLevel = loan.Approval_Level__c;
    view.approvalLevelLabel = label(loan.Approval_Level__c);
    view.decisionReason = loan.Decision_Reason__c;
    view.submittedDate = loan.Submitted_Date__c;
    view.decisionDate = loan.Decision_Date__c;
    view.actions = actionsFor(loan.Status__c);
    view.creditChecks = creditChecksFor(loan.Id);
    return view;
  }

  @AuraEnabled
  public static void changeStatus(
    Id loanId,
    String targetStatus,
    String reason
  ) {
    List<Loan_Application__c> loans = [
      SELECT Id, Status__c
      FROM Loan_Application__c
      WHERE Id = :loanId
      WITH USER_MODE
    ];
    if (loans.isEmpty()) {
      throw auraError('Loan application not found or not accessible.');
    }
    String currentStatus = loans[0].Status__c;
    LoanAction action = actionFor(currentStatus, targetStatus);
    if (action == null) {
      throw auraError(
        'This action isn\'t available while the application is ' +
          label(currentStatus) +
          '.'
      );
    }
    if (action.requiresReason && String.isBlank(reason)) {
      throw auraError('Please enter a reason.');
    }

    Loan_Application__c change = new Loan_Application__c(
      Id = loanId,
      Status__c = targetStatus
    );
    if (String.isNotBlank(reason)) {
      change.Decision_Reason__c = reason.trim();
    }
    try {
      update as user change;
    } catch (DmlException e) {
      throw auraError(e.getDmlMessage(0));
    }
  }

  /** Actions a user may take from the screen, most important first. */
  @TestVisible
  static List<LoanAction> actionsFor(String status) {
    List<LoanAction> actions = new List<LoanAction>();
    for (String target : LoanStatusMachine.allowedFrom(status)) {
      LoanAction action = actionFor(status, target);
      if (action != null) {
        actions.add(action);
      }
    }
    // Simple insertion sort by rank: the list never has more than a few items
    for (Integer i = 1; i < actions.size(); i++) {
      LoanAction current = actions[i];
      Integer j = i - 1;
      while (j >= 0 && actions[j].rank > current.rank) {
        actions[j + 1] = actions[j];
        j--;
      }
      actions[j + 1] = current;
    }
    return actions;
  }

  /**
   * The user-facing action for a transition, or null when the transition isn't allowed or belongs
   * to the system: everything that leaves Scoring is decided by the credit scoring job.
   */
  @TestVisible
  static LoanAction actionFor(String fromStatus, String toStatus) {
    if (
      fromStatus == LoanStatusMachine.SCORING ||
      !LoanStatusMachine.canTransition(fromStatus, toStatus) ||
      fromStatus == toStatus
    ) {
      return null;
    }
    if (
      toStatus == LoanStatusMachine.SUBMITTED &&
      fromStatus == LoanStatusMachine.DRAFT
    ) {
      return action(
        toStatus,
        'Submit application',
        'primary',
        'utility:send',
        1
      );
    }
    if (
      toStatus == LoanStatusMachine.SUBMITTED &&
      fromStatus == LoanStatusMachine.PENDING_APPROVAL
    ) {
      return action(
        toStatus,
        'Return for changes',
        'neutral',
        'utility:undo',
        3
      );
    }
    if (toStatus == LoanStatusMachine.SCORING) {
      return action(
        toStatus,
        'Run credit scoring',
        'primary',
        'utility:flash',
        1
      );
    }
    if (toStatus == LoanStatusMachine.APPROVED) {
      return action(toStatus, 'Approve', 'success', 'utility:check', 1);
    }
    if (toStatus == LoanStatusMachine.REJECTED) {
      LoanAction reject = action(
        toStatus,
        'Reject',
        'danger',
        'utility:close',
        2
      );
      reject.requiresReason = true;
      return reject;
    }
    if (toStatus == LoanStatusMachine.FUNDED) {
      return action(
        toStatus,
        'Mark as funded',
        'primary',
        'utility:moneybag',
        1
      );
    }
    if (toStatus == LoanStatusMachine.DRAFT) {
      return action(toStatus, 'Back to draft', 'neutral', 'utility:edit', 3);
    }
    return null;
  }

  private static LoanAction action(
    String target,
    String labelText,
    String style,
    String iconName,
    Integer rank
  ) {
    LoanAction action = new LoanAction();
    action.targetStatus = target;
    action.label = labelText;
    action.style = style;
    action.iconName = iconName;
    action.rank = rank;
    return action;
  }

  private static List<CreditCheckView> creditChecksFor(Id loanId) {
    List<CreditCheckView> views = new List<CreditCheckView>();
    for (Credit_Check__c check : [
      SELECT
        Id,
        Name,
        Status__c,
        Score__c,
        Response_Time_Ms__c,
        Error_Message__c,
        CreatedDate,
        Request_Id__c
      FROM Credit_Check__c
      WHERE Loan_Application__c = :loanId
      WITH USER_MODE
      ORDER BY CreatedDate DESC, Name DESC
      LIMIT 10
    ]) {
      CreditCheckView view = new CreditCheckView();
      view.id = check.Id;
      view.name = check.Name;
      view.status = check.Status__c;
      view.score = check.Score__c;
      view.responseTimeMs = check.Response_Time_Ms__c;
      view.errorMessage = check.Error_Message__c;
      view.createdDate = check.CreatedDate;
      view.requestId = check.Request_Id__c;
      views.add(view);
    }
    return views;
  }

  private static String label(String apiValue) {
    return apiValue == null ? null : apiValue.replace('_', ' ');
  }

  private static AuraHandledException auraError(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
