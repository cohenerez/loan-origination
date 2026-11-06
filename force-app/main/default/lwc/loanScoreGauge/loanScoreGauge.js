import { LightningElement, api } from "lwc";

const MIN_SCORE = 300;
const MAX_SCORE = 850;
// Length of the semicircle arc: radius 80 * PI
const ARC_LENGTH = 251.33;

export const TIERS = {
  A: { label: "Excellent", color: "#10b981", glow: "rgba(16, 185, 129, 0.45)" },
  B: { label: "Good", color: "#3b82f6", glow: "rgba(59, 130, 246, 0.45)" },
  C: { label: "Fair", color: "#f59e0b", glow: "rgba(245, 158, 11, 0.45)" },
  D: { label: "Poor", color: "#ef4444", glow: "rgba(239, 68, 68, 0.45)" }
};
const UNKNOWN_TIER = {
  label: "",
  color: "#64748b",
  glow: "rgba(100, 116, 139, 0.35)"
};

/**
 * Semicircle gauge for a credit score from 300 to 850, coloured by risk tier.
 */
export default class LoanScoreGauge extends LightningElement {
  @api score;
  @api tier;

  get hasScore() {
    return this.score !== null && this.score !== undefined && this.score !== "";
  }

  get displayScore() {
    return Math.round(Number(this.score));
  }

  get ratio() {
    const ratio = (Number(this.score) - MIN_SCORE) / (MAX_SCORE - MIN_SCORE);
    return Math.min(1, Math.max(0, ratio));
  }

  get tierInfo() {
    return TIERS[this.tier] || UNKNOWN_TIER;
  }

  get arcStyle() {
    const offset = (ARC_LENGTH * (1 - this.ratio)).toFixed(2);
    const { color, glow } = this.tierInfo;
    return `stroke-dashoffset: ${offset}; stroke: ${color}; filter: drop-shadow(0 0 6px ${glow});`;
  }

  get tierStyle() {
    const { color } = this.tierInfo;
    return `color: ${color}; background: ${color}1a; border-color: ${color}40;`;
  }

  get tierText() {
    if (!this.tier) {
      return "Scored";
    }
    return `Tier ${this.tier} · ${this.tierInfo.label}`;
  }
}
