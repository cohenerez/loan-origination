import { LightningElement, api } from "lwc";

const MAIN_FLOW = [
  "Draft",
  "Submitted",
  "Scoring",
  "Pending_Approval",
  "Approved",
  "Funded"
];
const REJECTED_FLOW = ["Draft", "Submitted", "Scoring", "Rejected"];

const LABELS = {
  Draft: "Draft",
  Submitted: "Submitted",
  Scoring: "Scoring",
  Pending_Approval: "Approval",
  Approved: "Approved",
  Funded: "Funded",
  Rejected: "Rejected"
};

/**
 * Progress indicator for the loan lifecycle. A rejected application shows a shorter path ending in red.
 */
export default class LoanStatusPath extends LightningElement {
  @api status;

  get flow() {
    return this.status === "Rejected" ? REJECTED_FLOW : MAIN_FLOW;
  }

  get currentIndex() {
    return Math.max(0, this.flow.indexOf(this.status));
  }

  get isFinished() {
    return this.status === "Funded" || this.status === "Rejected";
  }

  get steps() {
    const current = this.currentIndex;
    return this.flow.map((key, index) => {
      const isRejected = key === "Rejected" && index === current;
      const isComplete =
        index < current || (index === current && this.status === "Funded");
      let state = "upcoming";
      if (isRejected) {
        state = "rejected";
      } else if (isComplete) {
        state = "complete";
      } else if (index === current) {
        state = "current";
      }
      return {
        key,
        label: LABELS[key],
        number: index + 1,
        isComplete,
        isRejected,
        className: `step step-${state}`
      };
    });
  }

  /** The rail runs from the centre of the first marker to the centre of the last. */
  get railStyle() {
    const inset = (100 / (2 * this.flow.length)).toFixed(3);
    return `left: ${inset}%; right: ${inset}%;`;
  }

  get fillStyle() {
    const percent = (this.currentIndex / (this.flow.length - 1)) * 100;
    return `width: ${percent}%;`;
  }

  get fillClass() {
    return this.status === "Rejected" ? "fill fill-rejected" : "fill";
  }
}
