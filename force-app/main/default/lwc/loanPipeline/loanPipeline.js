import { LightningElement, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { refreshApex } from "@salesforce/apex";
import getPipeline from "@salesforce/apex/LoanPipelineController.getPipeline";
import LOCALE from "@salesforce/i18n/locale";
import CURRENCY from "@salesforce/i18n/currency";

const COMPACT_CURRENCY = new Intl.NumberFormat(LOCALE, {
  style: "currency",
  currency: CURRENCY,
  notation: "compact",
  minimumFractionDigits: 0,
  maximumFractionDigits: 1
});

export const STAGE_COLORS = {
  Draft: "#94a3b8",
  Submitted: "#3b82f6",
  Scoring: "#06b6d4",
  Pending_Approval: "#f59e0b",
  Approved: "#10b981",
  Funded: "#059669",
  Rejected: "#ef4444"
};

const STATUS_PILLS = {
  Draft: "pill pill-draft",
  Submitted: "pill pill-submitted",
  Scoring: "pill pill-scoring",
  Pending_Approval: "pill pill-pending",
  Approved: "pill pill-approved",
  Funded: "pill pill-funded",
  Rejected: "pill pill-rejected"
};

function reduceError(error) {
  if (Array.isArray(error?.body)) {
    return error.body.map((e) => e.message).join(", ");
  }
  return error?.body?.message || error?.message || "Unknown error";
}

/**
 * Home dashboard for loan officers: KPIs, the pipeline by stage and recent applications.
 */
export default class LoanPipeline extends NavigationMixin(LightningElement) {
  pipeline;
  error;
  selectedStatus;
  wiredResult;

  @wire(getPipeline)
  wiredPipeline(result) {
    this.wiredResult = result;
    if (result.data) {
      this.pipeline = result.data;
      this.error = undefined;
    } else if (result.error) {
      this.error = reduceError(result.error);
    }
  }

  // ---------- handlers ----------

  handleRefresh() {
    return refreshApex(this.wiredResult);
  }

  handleNew() {
    this[NavigationMixin.Navigate]({
      type: "standard__objectPage",
      attributes: { objectApiName: "Loan_Application__c", actionName: "new" }
    });
  }

  handleOpen(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: event.currentTarget.dataset.id,
        actionName: "view"
      }
    });
  }

  handleStageClick(event) {
    const status = event.currentTarget.dataset.status;
    this.selectedStatus = this.selectedStatus === status ? undefined : status;
  }

  clearFilter() {
    this.selectedStatus = undefined;
  }

  // ---------- KPIs ----------

  get openAmount() {
    return this.pipeline?.openAmount ?? 0;
  }

  get openCountText() {
    const count = this.pipeline?.openCount ?? 0;
    return count === 1 ? "1 open application" : `${count} open applications`;
  }

  get pendingApprovalCount() {
    return this.pipeline?.pendingApprovalCount ?? 0;
  }

  get approvalRateText() {
    const rate = this.pipeline?.approvalRate;
    return rate === null || rate === undefined ? "—" : `${rate}%`;
  }

  get decidedText() {
    const decided = this.pipeline?.decidedCount ?? 0;
    return decided === 0 ? "No decisions yet" : `Of ${decided} decided`;
  }

  get averageScoreText() {
    const score = this.pipeline?.averageScore;
    return score === null || score === undefined ? "—" : String(score);
  }

  get subtitle() {
    if (!this.pipeline) {
      return "Loading your pipeline…";
    }
    const total = this.pipeline.totalCount;
    return total === 1
      ? "1 application in total"
      : `${total} applications in total`;
  }

  // ---------- stages ----------

  get stages() {
    return (this.pipeline?.stages || []).map((stage) => ({
      ...stage,
      dotStyle: `background: ${STAGE_COLORS[stage.status]};`,
      amountText: COMPACT_CURRENCY.format(stage.amount || 0),
      className: [
        "lp-stage",
        stage.status === this.selectedStatus ? "lp-stage-active" : "",
        stage.count === 0 ? "lp-stage-empty" : ""
      ]
        .filter(Boolean)
        .join(" ")
    }));
  }

  get barSegments() {
    const stages = (this.pipeline?.stages || []).filter(
      (stage) => stage.count > 0
    );
    const total = stages.reduce((sum, stage) => sum + stage.count, 0);
    if (total === 0) {
      return [
        {
          status: "empty",
          style: "flex: 1; background: #e8edf5;",
          title: "No applications yet"
        }
      ];
    }
    return stages.map((stage) => ({
      status: stage.status,
      title: `${stage.label}: ${stage.count}`,
      style: `flex: ${stage.count} 1 0; background: ${STAGE_COLORS[stage.status]};`
    }));
  }

  // ---------- table ----------

  get rows() {
    return (this.pipeline?.recent || [])
      .filter(
        (row) => !this.selectedStatus || row.status === this.selectedStatus
      )
      .map((row) => ({
        ...row,
        applicantText: row.applicantName || "—",
        lastModifiedTime: row.lastModified
          ? new Date(row.lastModified).getTime()
          : null,
        pillClass: STATUS_PILLS[row.status] || "pill",
        scoreText:
          row.creditScore === null || row.creditScore === undefined
            ? "—"
            : String(Math.round(row.creditScore)),
        scoreClass: `score score-${(row.riskTier || "none").toLowerCase()}`
      }));
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get tableTitle() {
    if (!this.selectedStatus) {
      return "Recent applications";
    }
    const stage = (this.pipeline?.stages || []).find(
      (s) => s.status === this.selectedStatus
    );
    return `Recent applications · ${stage ? stage.label : this.selectedStatus}`;
  }

  get emptyText() {
    return this.selectedStatus
      ? "No recent applications in this stage."
      : "No applications yet. Create the first one with New application.";
  }
}
