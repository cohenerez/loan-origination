import { LightningElement, api, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import getLoanView from "@salesforce/apex/LoanApplicationController.getLoanView";
import changeStatus from "@salesforce/apex/LoanApplicationController.changeStatus";
import checkHealth from "@salesforce/apex/CreditScoringHealthCheck.check";

const POLL_INTERVAL_MS = 3000;
const POLL_TIMEOUT_MS = 60000;

const STATUS_CLASSES = {
  Draft: "status-draft",
  Submitted: "status-submitted",
  Scoring: "status-scoring",
  Pending_Approval: "status-pending",
  Approved: "status-approved",
  Funded: "status-funded",
  Rejected: "status-rejected"
};

/** Turns any Apex, wire or JS error into one readable sentence. */
export function reduceError(error) {
  if (!error) {
    return "Unknown error";
  }
  if (Array.isArray(error.body)) {
    return error.body.map((e) => e.message).join(", ");
  }
  if (error.body && typeof error.body.message === "string") {
    return error.body.message;
  }
  if (typeof error.message === "string") {
    return error.message;
  }
  return "Unknown error";
}

/**
 * Command center for a loan application: progress, credit score, the actions allowed right now,
 * scoring history and the live status of the scoring service. While the application is in
 * Scoring it polls until the background job finishes.
 */
export default class LoanCommandCenter extends LightningElement {
  @api recordId;

  view;
  error;
  busy = false;
  pendingAction;
  reason = "";
  reasonError;
  health;
  healthChecking = false;

  wiredResult;
  pollTimer;
  pollStartedAt;

  @wire(getLoanView, { loanId: "$recordId" })
  wiredView(result) {
    this.wiredResult = result;
    const { data, error } = result;
    if (data) {
      const previousStatus = this.view?.status;
      this.view = data;
      this.error = undefined;
      this.onStatus(previousStatus);
    } else if (error) {
      this.error = reduceError(error);
    }
  }

  connectedCallback() {
    this.runHealthCheck();
  }

  disconnectedCallback() {
    this.stopPolling();
  }

  // ---------- live updates ----------

  onStatus(previousStatus) {
    if (this.view.status === "Scoring") {
      this.startPolling();
      return;
    }
    this.stopPolling();
    if (previousStatus === "Scoring") {
      notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
      const failed = this.view.status === "Submitted";
      this.toast(
        failed ? "Credit scoring failed" : "Credit scoring complete",
        failed
          ? "The scoring service could not be reached. See the scoring history, then try again."
          : `${this.view.name} is now ${this.view.statusLabel}.`,
        failed ? "warning" : "success"
      );
    }
  }

  startPolling() {
    if (this.pollTimer) {
      return;
    }
    this.pollStartedAt = Date.now();
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.pollTimer = setInterval(() => {
      if (Date.now() - this.pollStartedAt > POLL_TIMEOUT_MS) {
        this.stopPolling();
        return;
      }
      refreshApex(this.wiredResult);
    }, POLL_INTERVAL_MS);
  }

  stopPolling() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = undefined;
    }
  }

  async runHealthCheck() {
    this.healthChecking = true;
    try {
      this.health = await checkHealth();
    } catch (e) {
      this.health = { up: false, errorMessage: reduceError(e) };
    } finally {
      this.healthChecking = false;
    }
  }

  // ---------- actions ----------

  handleAction(event) {
    const target = event.currentTarget.dataset.status;
    const action = (this.view.actions || []).find(
      (a) => a.targetStatus === target
    );
    if (!action) {
      return;
    }
    if (action.requiresReason) {
      this.pendingAction = action;
      this.reason = "";
      this.reasonError = undefined;
      return;
    }
    this.submit(action, null);
  }

  handleReasonChange(event) {
    this.reason = event.detail.value;
    this.reasonError = undefined;
  }

  cancelReason() {
    this.pendingAction = undefined;
    this.reasonError = undefined;
  }

  confirmReason() {
    if (!this.reason || !this.reason.trim()) {
      this.reasonError = "Please enter a reason.";
      return;
    }
    this.submit(this.pendingAction, this.reason.trim());
  }

  async submit(action, reason) {
    this.busy = true;
    try {
      await changeStatus({
        loanId: this.recordId,
        targetStatus: action.targetStatus,
        reason
      });
      this.pendingAction = undefined;
      await refreshApex(this.wiredResult);
      notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
      this.toast(
        action.label,
        `${this.view.name} is now ${this.view.statusLabel}.`,
        "success"
      );
    } catch (e) {
      this.toast(`${action.label} failed`, reduceError(e), "error");
    } finally {
      this.busy = false;
    }
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  // ---------- view state ----------

  get isLoading() {
    return !this.view && !this.error;
  }

  get isScoring() {
    return this.view?.status === "Scoring";
  }

  get statusPillClass() {
    return `status-pill ${STATUS_CLASSES[this.view.status] || ""}`;
  }

  get applicantText() {
    return this.view.applicantName || "No applicant selected";
  }

  get termText() {
    return this.view.termMonths ? `${this.view.termMonths} months` : "—";
  }

  get purposeText() {
    return this.view.purpose || "—";
  }

  get healthState() {
    if (this.healthChecking || !this.health) {
      return "checking";
    }
    return this.health.up ? "up" : "down";
  }

  get healthChipClass() {
    return `health-chip health-${this.healthState}`;
  }

  get healthLabel() {
    switch (this.healthState) {
      case "up":
        return `Scoring service online · ${this.health.elapsedMs} ms`;
      case "down":
        return "Scoring service offline";
      default:
        return "Checking scoring service…";
    }
  }

  get healthTitle() {
    return (
      this.health?.errorMessage || "Click to check the scoring service again"
    );
  }

  get tierBadgeClass() {
    return `tier-badge tier-${(this.view.riskTier || "none").toLowerCase()}`;
  }

  get tierBadgeText() {
    return this.view.riskTier
      ? `Risk tier ${this.view.riskTier}`
      : "Not scored";
  }

  get approvalLevelText() {
    return this.view.approvalLevelLabel || "—";
  }

  get decisionText() {
    if (this.view.decisionReason) {
      return this.view.decisionReason;
    }
    if (
      this.view.status === "Pending_Approval" &&
      this.view.approvalLevelLabel
    ) {
      return `Awaiting ${this.view.approvalLevelLabel} approval`;
    }
    if (this.view.status === "Scoring") {
      return "Scoring in progress";
    }
    return "—";
  }

  get loanToIncomeText() {
    const ratio = this.view.loanToIncome;
    return ratio === null || ratio === undefined
      ? "—"
      : `${Number(ratio).toFixed(2)}×`;
  }

  get loanToIncomeClass() {
    const ratio = Number(this.view.loanToIncome);
    if (ratio > 5) {
      return "tile-value tone-danger";
    }
    if (ratio > 3) {
      return "tile-value tone-warn";
    }
    return "tile-value";
  }

  get actions() {
    return (this.view.actions || []).map((action) => ({
      ...action,
      className: `action action-${action.style}`,
      iconVariant: action.style === "neutral" ? "" : "inverse"
    }));
  }

  get hasActions() {
    return this.actions.length > 0;
  }

  get reasonLabel() {
    return `Reason for ${this.pendingAction?.label?.toLowerCase() || "decision"}`;
  }

  get isClosed() {
    return this.view.status === "Funded" || this.view.status === "Rejected";
  }

  get closedClass() {
    return `closed-banner closed-${this.view.status === "Funded" ? "funded" : "rejected"}`;
  }

  get closedIcon() {
    return this.view.status === "Funded" ? "utility:success" : "utility:ban";
  }

  get closedTitle() {
    return this.view.status === "Funded"
      ? "Loan funded"
      : "Application rejected";
  }

  get closedSubtitle() {
    return this.view.status === "Funded"
      ? "The funds have been released. This application is closed."
      : this.view.decisionReason || "This application is closed.";
  }

  get checks() {
    return (this.view.creditChecks || []).map((check) => ({
      ...check,
      itemClass: `timeline-item check-${(check.status || "unknown").toLowerCase()}`,
      scoreText:
        check.score === null || check.score === undefined
          ? "—"
          : `Score ${Math.round(check.score)}`,
      timeText:
        check.responseTimeMs === null || check.responseTimeMs === undefined
          ? ""
          : `${Math.round(check.responseTimeMs)} ms`
    }));
  }

  get hasChecks() {
    return this.checks.length > 0;
  }

  get checksCountText() {
    const count = this.checks.length;
    return count === 1 ? "1 run" : `${count} runs`;
  }
}
