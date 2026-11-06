/**
 * Backend for the loanPipeline home dashboard: KPIs, the pipeline by status and recent applications.
 * Everything runs in user mode, so each officer sees only the applications they have access to.
 */
public with sharing class LoanPipelineController {
  /** Lifecycle order, used to sort the stages. */
  @TestVisible
  static final List<String> STAGE_ORDER = new List<String>{
    LoanStatusMachine.DRAFT,
    LoanStatusMachine.SUBMITTED,
    LoanStatusMachine.SCORING,
    LoanStatusMachine.PENDING_APPROVAL,
    LoanStatusMachine.APPROVED,
    LoanStatusMachine.FUNDED,
    LoanStatusMachine.REJECTED
  };

  private static final Set<String> CLOSED = new Set<String>{
    LoanStatusMachine.FUNDED,
    LoanStatusMachine.REJECTED
  };

  public class Stage {
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Integer count = 0;
    @AuraEnabled
    public Decimal amount = 0;
  }

  public class LoanRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String applicantName;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String statusLabel;
    @AuraEnabled
    public Decimal creditScore;
    @AuraEnabled
    public String riskTier;
    @AuraEnabled
    public String approvalLevelLabel;
    @AuraEnabled
    public Datetime lastModified;
  }

  public class Pipeline {
    @AuraEnabled
    public Integer totalCount = 0;
    @AuraEnabled
    public Integer openCount = 0;
    @AuraEnabled
    public Decimal openAmount = 0;
    @AuraEnabled
    public Integer pendingApprovalCount = 0;
    @AuraEnabled
    public Decimal approvalRate;
    @AuraEnabled
    public Integer decidedCount = 0;
    @AuraEnabled
    public Decimal averageScore;
    @AuraEnabled
    public List<Stage> stages = new List<Stage>();
    @AuraEnabled
    public List<LoanRow> recent = new List<LoanRow>();
  }

  @AuraEnabled(cacheable=true)
  public static Pipeline getPipeline() {
    Pipeline pipeline = new Pipeline();

    Map<String, Stage> byStatus = new Map<String, Stage>();
    for (String status : STAGE_ORDER) {
      Stage stage = new Stage();
      stage.status = status;
      stage.label = status.replace('_', ' ');
      byStatus.put(status, stage);
      pipeline.stages.add(stage);
    }

    for (AggregateResult row : [
      SELECT Status__c status, COUNT(Id) total, SUM(Amount__c) amount
      FROM Loan_Application__c
      WITH USER_MODE
      GROUP BY Status__c
    ]) {
      Stage stage = byStatus.get((String) row.get('status'));
      if (stage == null) {
        continue;
      }
      stage.count = (Integer) row.get('total');
      stage.amount = row.get('amount') == null
        ? 0
        : (Decimal) row.get('amount');
    }

    Integer approved = 0;
    for (Stage stage : pipeline.stages) {
      pipeline.totalCount += stage.count;
      if (!CLOSED.contains(stage.status)) {
        pipeline.openCount += stage.count;
        pipeline.openAmount += stage.amount;
      }
      if (
        stage.status == LoanStatusMachine.APPROVED ||
        stage.status == LoanStatusMachine.FUNDED
      ) {
        approved += stage.count;
      }
    }
    pipeline.pendingApprovalCount = byStatus.get(
        LoanStatusMachine.PENDING_APPROVAL
      )
      .count;
    pipeline.decidedCount =
      approved + byStatus.get(LoanStatusMachine.REJECTED).count;
    if (pipeline.decidedCount > 0) {
      pipeline.approvalRate = (Decimal.valueOf(approved) *
        100 /
        pipeline.decidedCount)
        .setScale(0);
    }

    AggregateResult scores = [
      SELECT AVG(Credit_Score__c) average
      FROM Loan_Application__c
      WHERE Credit_Score__c != NULL
      WITH USER_MODE
    ];
    Object average = scores.get('average');
    pipeline.averageScore = average == null
      ? null
      : ((Decimal) average).setScale(0);

    for (Loan_Application__c loan : [
      SELECT
        Id,
        Name,
        Applicant__r.Name,
        Amount__c,
        Status__c,
        Credit_Score__c,
        Risk_Tier__c,
        Approval_Level__c,
        LastModifiedDate
      FROM Loan_Application__c
      WITH USER_MODE
      ORDER BY LastModifiedDate DESC
      LIMIT 25
    ]) {
      LoanRow row = new LoanRow();
      row.id = loan.Id;
      row.name = loan.Name;
      row.applicantName = loan.Applicant__r?.Name;
      row.amount = loan.Amount__c;
      row.status = loan.Status__c;
      row.statusLabel = loan.Status__c?.replace('_', ' ');
      row.creditScore = loan.Credit_Score__c;
      row.riskTier = loan.Risk_Tier__c;
      row.approvalLevelLabel = loan.Approval_Level__c?.replace('_', ' ');
      row.lastModified = loan.LastModifiedDate;
      pipeline.recent.add(row);
    }
    return pipeline;
  }
}
