package com.erez.loans.scoring.engine;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import org.junit.jupiter.api.Test;

class ScoringEngineTest {

    private final ScoringEngine engine = new ScoringEngine();

    private static LoanFacts facts(String loanId, String amount, int term, String income, String purpose) {
        return new LoanFacts(loanId, new BigDecimal(amount), term, new BigDecimal(income), purpose);
    }

    @Test
    void strongApplicantGetsTopTiers() {
        ScoringResult result = engine.score(facts("a0X000000000001", "50000", 60, "25000", "Auto"));

        assertThat(result.score()).isGreaterThanOrEqualTo(700);
        assertThat(result.riskTier()).isIn(RiskTier.A, RiskTier.B);
        assertThat(result.reasons()).contains("Low payment-to-income ratio");
    }

    @Test
    void overstretchedApplicantGetsTierD() {
        ScoringResult result = engine.score(facts("a0X000000000002", "500000", 60, "8000", "Business"));

        assertThat(result.riskTier()).isEqualTo(RiskTier.D);
        assertThat(result.reasons()).contains("Payment exceeds half of monthly income");
    }

    @Test
    void sameLoanAlwaysGetsSameScore() {
        LoanFacts facts = facts("a0X000000000003", "120000", 120, "15000", "Mortgage");

        assertThat(engine.score(facts)).isEqualTo(engine.score(facts));
    }

    @Test
    void scoreStaysWithinRange() {
        ScoringResult worst = engine.score(facts("x", "10000000", 360, "100", "Business"));
        ScoringResult best = engine.score(facts("y", "1000", 6, "1000000", "Mortgage"));

        assertThat(worst.score()).isBetween(ScoringEngine.MIN_SCORE, ScoringEngine.MAX_SCORE);
        assertThat(best.score()).isBetween(ScoringEngine.MIN_SCORE, ScoringEngine.MAX_SCORE);
    }

    @Test
    void monthlyPaymentMatchesAmortizationFormula() {
        // 100,000 over 60 months at 6% is 1,933.28 per month
        BigDecimal payment = ScoringEngine.monthlyPayment(new BigDecimal("100000"), 60);

        assertThat(payment.setScale(2, java.math.RoundingMode.HALF_UP)).isEqualByComparingTo("1933.28");
    }

    @Test
    void tierBoundaries() {
        assertThat(RiskTier.fromScore(740)).isEqualTo(RiskTier.A);
        assertThat(RiskTier.fromScore(739)).isEqualTo(RiskTier.B);
        assertThat(RiskTier.fromScore(680)).isEqualTo(RiskTier.B);
        assertThat(RiskTier.fromScore(620)).isEqualTo(RiskTier.C);
        assertThat(RiskTier.fromScore(619)).isEqualTo(RiskTier.D);
    }
}
