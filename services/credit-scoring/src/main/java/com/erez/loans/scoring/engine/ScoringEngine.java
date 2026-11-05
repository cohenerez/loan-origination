package com.erez.loans.scoring.engine;

import java.math.BigDecimal;
import java.math.MathContext;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import org.springframework.stereotype.Component;


@Component
public class ScoringEngine {

    static final int BASE_SCORE = 700;
    static final int MIN_SCORE = 300;
    static final int MAX_SCORE = 850;
    static final BigDecimal ANNUAL_RATE = new BigDecimal("0.06");

    public ScoringResult score(LoanFacts facts) {
        List<String> reasons = new ArrayList<>();
        int score = BASE_SCORE;

        BigDecimal payment = monthlyPayment(facts.amount(), facts.termMonths());
        BigDecimal dti = payment.divide(facts.monthlyIncome(), 4, RoundingMode.HALF_UP);
        double dtiValue = dti.doubleValue();

        if (dtiValue <= 0.20) {
            score += 60;
            reasons.add("Low payment-to-income ratio");
        } else if (dtiValue <= 0.30) {
            score += 30;
        } else if (dtiValue <= 0.40) {
            reasons.add("Moderate payment-to-income ratio");
        } else if (dtiValue <= 0.50) {
            score -= 60;
            reasons.add("High payment-to-income ratio");
        } else {
            score -= 140;
            reasons.add("Payment exceeds half of monthly income");
        }

        BigDecimal annualIncome = facts.monthlyIncome().multiply(BigDecimal.valueOf(12));
        double loanToIncome = facts.amount().divide(annualIncome, 4, RoundingMode.HALF_UP).doubleValue();
        if (loanToIncome > 5) {
            score -= 40;
            reasons.add("Loan amount above 5x annual income");
        } else if (loanToIncome > 3) {
            score -= 15;
            reasons.add("Loan amount above 3x annual income");
        }

        if (facts.termMonths() > 240) {
            score -= 10;
            reasons.add("Long repayment term");
        }

        score += purposeAdjustment(facts.purpose(), reasons);
        score += stableJitter(facts.loanId());

        score = Math.max(MIN_SCORE, Math.min(MAX_SCORE, score));
        return new ScoringResult(score, RiskTier.fromScore(score),
                payment.setScale(2, RoundingMode.HALF_UP), dti, List.copyOf(reasons));
    }


    static BigDecimal monthlyPayment(BigDecimal principal, int termMonths) {
        MathContext mc = MathContext.DECIMAL64;
        BigDecimal r = ANNUAL_RATE.divide(BigDecimal.valueOf(12), mc);
        BigDecimal factor = BigDecimal.ONE.add(r).pow(termMonths, mc);
        return principal.multiply(r).multiply(factor).divide(factor.subtract(BigDecimal.ONE), mc);
    }

    private static int purposeAdjustment(String purpose, List<String> reasons) {
        String p = purpose == null ? "" : purpose.toLowerCase(Locale.ROOT);
        return switch (p) {
            case "mortgage" -> { reasons.add("Secured by property"); yield 15; }
            case "auto" -> 5;
            case "business" -> { reasons.add("Business purpose carries higher risk"); yield -20; }
            default -> -10;
        };
    }


    private static int stableJitter(String loanId) {
        return Math.floorMod(loanId.hashCode(), 51) - 25;
    }
}
