package com.erez.loans.scoring.engine;

import java.math.BigDecimal;


public record LoanFacts(String loanId, BigDecimal amount, int termMonths, BigDecimal monthlyIncome, String purpose) {
}
