import { createElement } from "lwc";
import LoanScoreGauge from "c/loanScoreGauge";

function render(props) {
  const element = createElement("c-loan-score-gauge", { is: LoanScoreGauge });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

describe("c-loan-score-gauge", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows the empty state when there is no score", () => {
    const element = render({});

    expect(
      element.shadowRoot.querySelector('[data-id="empty"]').textContent
    ).toBe("Not scored yet");
    expect(element.shadowRoot.querySelector(".value")).toBeNull();
  });

  it("shows the rounded score and the tier label", () => {
    const element = render({ score: 731.4, tier: "B" });

    expect(
      element.shadowRoot.querySelector('[data-id="score"]').textContent
    ).toBe("731");
    expect(
      element.shadowRoot.querySelector('[data-id="tier"]').textContent
    ).toBe("Tier B · Good");
  });

  it("fills the arc in proportion to the score and colours it by tier", () => {
    const element = render({ score: 850, tier: "A" });
    const style = element.shadowRoot
      .querySelector(".value")
      .getAttribute("style");

    expect(style).toContain("stroke-dashoffset: 0.00");
    expect(style).toContain("#10b981");
  });

  it("clamps scores outside 300-850", () => {
    const element = render({ score: 120, tier: "D" });
    const style = element.shadowRoot
      .querySelector(".value")
      .getAttribute("style");

    expect(style).toContain("stroke-dashoffset: 251.33");
  });
});
