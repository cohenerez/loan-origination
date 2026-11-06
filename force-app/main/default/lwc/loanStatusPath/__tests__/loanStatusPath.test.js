import { createElement } from "lwc";
import LoanStatusPath from "c/loanStatusPath";

function render(status) {
  const element = createElement("c-loan-status-path", { is: LoanStatusPath });
  element.status = status;
  document.body.appendChild(element);
  return element;
}

function stepClass(element, key) {
  return element.shadowRoot.querySelector(`[data-step="${key}"]`).className;
}

describe("c-loan-status-path", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("marks earlier steps complete and the current step active", () => {
    const element = render("Pending_Approval");

    expect(element.shadowRoot.querySelectorAll("li")).toHaveLength(6);
    expect(stepClass(element, "Submitted")).toContain("step-complete");
    expect(stepClass(element, "Pending_Approval")).toContain("step-current");
    expect(stepClass(element, "Funded")).toContain("step-upcoming");
  });

  it("shows a shorter path ending in red for a rejected application", () => {
    const element = render("Rejected");

    expect(element.shadowRoot.querySelectorAll("li")).toHaveLength(4);
    expect(stepClass(element, "Rejected")).toContain("step-rejected");
    expect(element.shadowRoot.querySelector(".fill").className).toContain(
      "fill-rejected"
    );
  });

  it("fills the whole rail and completes every step when funded", () => {
    const element = render("Funded");

    expect(stepClass(element, "Funded")).toContain("step-complete");
    expect(
      element.shadowRoot.querySelector(".fill").getAttribute("style")
    ).toContain("width: 100%");
  });
});
