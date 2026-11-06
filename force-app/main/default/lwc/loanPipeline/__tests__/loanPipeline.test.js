import { createElement } from "lwc";
import LoanPipeline from "c/loanPipeline";
import getPipeline from "@salesforce/apex/LoanPipelineController.getPipeline";

const mockNavigate = jest.fn();
jest.mock(
  "lightning/navigation",
  () => {
    const Navigate = Symbol("Navigate");
    const NavigationMixin = (Base) =>
      class extends Base {
        [Navigate](pageReference) {
          mockNavigate(pageReference);
        }
      };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin };
  },
  { virtual: true }
);
const getNavigateCalledWith = () => ({
  pageReference: mockNavigate.mock.calls.at(-1)[0]
});

jest.mock(
  "@salesforce/apex/LoanPipelineController.getPipeline",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const stage = (status, label, count, amount) => ({
  status,
  label,
  count,
  amount
});

const PIPELINE = {
  totalCount: 9,
  openCount: 8,
  openAmount: 470000,
  pendingApprovalCount: 3,
  approvalRate: 75,
  decidedCount: 4,
  averageScore: 712,
  stages: [
    stage("Draft", "Draft", 2, 20000),
    stage("Submitted", "Submitted", 0, 0),
    stage("Scoring", "Scoring", 0, 0),
    stage("Pending_Approval", "Pending Approval", 3, 300000),
    stage("Approved", "Approved", 3, 150000),
    stage("Funded", "Funded", 0, 0),
    stage("Rejected", "Rejected", 1, 400000)
  ],
  recent: [
    {
      id: "a01000000000001AAA",
      name: "LA-000009",
      applicantName: "Dana Levi",
      amount: 150000,
      status: "Pending_Approval",
      statusLabel: "Pending Approval",
      creditScore: 731,
      riskTier: "B",
      lastModified: "2026-11-06T10:00:00.000Z"
    },
    {
      id: "a01000000000002AAA",
      name: "LA-000008",
      applicantName: "Noam Cohen",
      amount: 30000,
      status: "Approved",
      statusLabel: "Approved",
      creditScore: 765,
      riskTier: "A",
      lastModified: "2026-11-06T09:00:00.000Z"
    },
    {
      id: "a01000000000003AAA",
      name: "LA-000007",
      amount: 12000,
      status: "Draft",
      statusLabel: "Draft",
      lastModified: "2026-11-06T08:00:00.000Z"
    }
  ]
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render(data = PIPELINE) {
  const element = createElement("c-loan-pipeline", { is: LoanPipeline });
  document.body.appendChild(element);
  getPipeline.emit(data);
  await flushPromises();
  return element;
}

describe("c-loan-pipeline", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows the KPIs", async () => {
    const root = (await render()).shadowRoot;

    expect(root.querySelector('[data-id="pending"]').textContent).toBe("3");
    expect(root.querySelector('[data-id="approval-rate"]').textContent).toBe(
      "75%"
    );
    expect(root.querySelector('[data-id="average-score"]').textContent).toBe(
      "712"
    );
    expect(root.querySelector('[data-id="subtitle"]').textContent).toBe(
      "9 applications in total"
    );
  });

  it("draws one bar segment per non-empty stage and a chip per stage", async () => {
    const root = (await render()).shadowRoot;

    expect(root.querySelectorAll(".lp-segment")).toHaveLength(4);
    expect(root.querySelectorAll(".lp-stage")).toHaveLength(7);
    expect(
      root.querySelector('button[data-status="Submitted"]').className
    ).toContain("lp-stage-empty");
  });

  it("filters the table when a stage is clicked, and clears it again", async () => {
    const root = (await render()).shadowRoot;
    expect(root.querySelectorAll(".row.body")).toHaveLength(3);

    root.querySelector('button[data-status="Approved"]').click();
    await flushPromises();
    expect(root.querySelectorAll(".row.body")).toHaveLength(1);
    expect(root.querySelector(".row.body .cell-name").textContent).toBe(
      "LA-000008"
    );
    expect(
      root.querySelector('button[data-status="Approved"]').className
    ).toContain("lp-stage-active");

    root.querySelector(".clear-filter").click();
    await flushPromises();
    expect(root.querySelectorAll(".row.body")).toHaveLength(3);
  });

  it("opens an application when its row is clicked", async () => {
    const root = (await render()).shadowRoot;

    root.querySelector(".row.body").click();

    const { pageReference } = getNavigateCalledWith();
    expect(pageReference.type).toBe("standard__recordPage");
    expect(pageReference.attributes.recordId).toBe("a01000000000001AAA");
  });

  it("opens the new application form", async () => {
    const root = (await render()).shadowRoot;

    root.querySelector('[data-id="new"]').click();

    const { pageReference } = getNavigateCalledWith();
    expect(pageReference.type).toBe("standard__objectPage");
    expect(pageReference.attributes).toEqual({
      objectApiName: "Loan_Application__c",
      actionName: "new"
    });
  });

  it("handles an empty org", async () => {
    const root = (
      await render({
        totalCount: 0,
        openCount: 0,
        openAmount: 0,
        pendingApprovalCount: 0,
        decidedCount: 0,
        stages: PIPELINE.stages.map((s) => ({ ...s, count: 0, amount: 0 })),
        recent: []
      })
    ).shadowRoot;

    expect(root.querySelector('[data-id="approval-rate"]').textContent).toBe(
      "—"
    );
    expect(root.querySelector('[data-id="empty"]')).not.toBeNull();
    expect(root.querySelectorAll(".lp-segment")).toHaveLength(1);
  });
});
