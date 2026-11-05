package com.erez.loans.scoring.api;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;


public record CreditScoreRequest(
        @NotBlank @Size(max = 64) String requestId,
        @NotBlank @Size(max = 18) String loanId,
        @NotNull @DecimalMin(value = "0.01") BigDecimal amount,
        @NotNull @Min(6) @Max(360) Integer termMonths,
        @NotNull @DecimalMin(value = "0.01") BigDecimal monthlyIncome,
        @Size(max = 40) String purpose) {
}
