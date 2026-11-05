package com.erez.loans.scoring.engine;

import java.math.BigDecimal;
import java.util.List;

public record ScoringResult(int score, RiskTier riskTier, BigDecimal monthlyPayment, BigDecimal debtToIncome, List<String> reasons) {

}
