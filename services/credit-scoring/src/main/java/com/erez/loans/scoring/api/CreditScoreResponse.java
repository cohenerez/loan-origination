package com.erez.loans.scoring.api;

import com.erez.loans.scoring.engine.RiskTier;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;

public record CreditScoreResponse(
        String requestId,
        String loanId,
        int score,
        RiskTier riskTier,
        BigDecimal monthlyPayment,
        BigDecimal debtToIncome,
        List<String> reasons,
        String modelVersion,
        Instant scoredAt) {
}
