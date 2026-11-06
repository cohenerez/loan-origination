import { createElement } from "lwc";
import LoanCommandCenter, { reduceError } from "c/loanCommandCenter";
import getLoanView from "@salesforce/apex/LoanApplicationController.getLoanView";
import changeStatus from "@salesforce/apex/LoanApplicationController.changeStatus";
import checkHealth from "@salesforce/apex/CreditScoringHealthCheck.check";

jest.mock(
  "@salesforce/apex/LoanApplicationController.getLoanView",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LoanApplicationController.changeStatus",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/CreditScoringHealthCheck.check",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);

const PENDING_VIEW = {
  id: "a01000000000001AAA",
  name: "LA-000002",
  status: "Pending_Approval",
  statusLabel: "Pending Approval",
  applicantName: "Dana Levi",
  amount: 150000,
  termMonths: 60,
  monthlyIncome: 15000,
  loanToIncome: 0.83,
  purpose: "Personal",
  creditScore: 731,
  riskTier: "B",
  approvalLevel: "Branch_Manager",
  approvalLevelLabel: "Branch Manager",
  actions: [
    {
      targetStatus: "Approved",
      label: "Approve",
      style: "success",
      iconName: "utility:check",
      requiresReason: false
    },
    {
      targetStatus: "Rejected",
      label: "Reject",
      style: "danger",
      iconName: "utility:close",
      requiresReason: true
    },
    {
      targetStatus: "Submitted",
      label: "Return for changes",
      style: "neutral",
      iconName: "utility:undo",
      requiresReason: false
    }
  ],
  creditChecks: [
    {
      id: "a02000000000001AAA",
      name: "CC-000003",
      status: "Success",
      score: 731,
      responseTimeMs: 412,
      createdDate: "2026-11-05T13:31:00.000Z"
    },
    {
      id: "a02000000000002AAA",
      name: "CC-000002",
      status: "Failed",
      errorMessage: "HTTP 404 Not Found",
      responseTimeMs: 380,
      createdDate: "2026-11-05T13:29:00.000Z"
    }
  ]
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function render() {
  const element = createElement("c-loan-command-center", {
    is: LoanCommandCenter
  });
  element.recordId = PENDING_VIEW.id;
  document.body.appendChild(element);
  return element;
}

describe("c-loan-command-center", () => {
  beforeEach(() => {
    checkHealth.mockResolvedValue({
      up: true,
      statusCode: 200,
      elapsedMs: 412
    });
    changeStatus.mockResolvedValue(undefined);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders the application, the score and the allowed actions", async () => {
    const element = render();
    getLoanView.emit(PENDING_VIEW);
    await flushPromises();

    const root = element.shadowRoot;
    expect(root.querySelector('[data-id="name"]').textContent).toBe(
      "LA-000002"
    );
    expect(root.querySelector('[data-id="status"]').textContent).toBe(
      "Pending Approval"
    );
    expect(root.querySelector('[data-id="decision"]').textContent).toBe(
      "Awaiting Branch Manager approval"
    );
    expect(root.querySelector("c-loan-score-gauge").score).toBe(731);

    const labels = Array.from(root.querySelectorAll(".actions button")).map(
      (b) => b.textContent.trim()
    );
    expect(labels).toEqual(["Approve", "Reject", "Return for changes"]);
    expect(root.querySelectorAll(".timeline-item")).toHaveLength(2);
  });

  it("shows the scoring service as online", async () => {
    const element = render();
    getLoanView.emit(PENDING_VIEW);
    await flushPromises();

    const chip = element.shadowRoot.querySelector(".health-chip");
    expect(chip.className).toContain("health-up");
    expect(chip.textContent).toContain("online");
  });

  it("approves without asking for a reason", async () => {
    const element = render();
    getLoanView.emit(PENDING_VIEW);
    await flushPromises();

    element.shadowRoot.querySelector('button[data-status="Approved"]').click();
    await flushPromises();

    expect(changeStatus).toHaveBeenCalledWith({
      loanId: PENDING_VIEW.id,
      targetStatus: "Approved",
      reason: null
    });
  });

  it("asks for a reason before rejecting", async () => {
    const element = render();
    getLoanView.emit(PENDING_VIEW);
    await flushPromises();
    const root = element.shadowRoot;

    root.querySelector('button[data-status="Rejected"]').click();
    await flushPromises();
    expect(root.querySelector(".reason-panel")).not.toBeNull();

    // Confirming without a reason shows an error and doesn't call Apex
    root.querySelector(".reason-buttons .action-danger").click();
    await flushPromises();
    expect(root.querySelector('[data-id="reason-error"]').textContent).toBe(
      "Please enter a reason."
    );
    expect(changeStatus).not.toHaveBeenCalled();

    const textarea = root.querySelector("lightning-textarea");
    textarea.dispatchEvent(
      new CustomEvent("change", {
        detail: { value: "Income could not be verified" }
      })
    );
    root.querySelector(".reason-buttons .action-danger").click();
    await flushPromises();

    expect(changeStatus).toHaveBeenCalledWith({
      loanId: PENDING_VIEW.id,
      targetStatus: "Rejected",
      reason: "Income could not be verified"
    });
  });

  it("shows the live banner while scoring", async () => {
    const element = render();
    getLoanView.emit({
      ...PENDING_VIEW,
      status: "Scoring",
      statusLabel: "Scoring",
      actions: []
    });
    await flushPromises();

    expect(element.shadowRoot.querySelector(".scoring-banner")).not.toBeNull();
    expect(element.shadowRoot.querySelector(".actions")).toBeNull();
  });

  it("shows a readable error when the record cannot be loaded", async () => {
    const element = render();
    getLoanView.error({
      message: "Loan application not found or not accessible."
    });
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(".error-card").textContent
    ).toContain("not found");
  });

  it("reduces Apex errors to a sentence", () => {
    expect(reduceError({ body: { message: "Boom" } })).toBe("Boom");
    expect(reduceError({ body: [{ message: "A" }, { message: "B" }] })).toBe(
      "A, B"
    );
    expect(reduceError(new Error("Plain"))).toBe("Plain");
    expect(reduceError(undefined)).toBe("Unknown error");
  });
});
