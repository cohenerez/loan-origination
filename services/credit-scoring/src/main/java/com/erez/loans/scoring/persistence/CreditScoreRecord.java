package com.erez.loans.scoring.persistence;

import com.erez.loans.scoring.engine.RiskTier;
import jakarta.persistence.Column;
import jakarta.persistence.Convert;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(name = "credit_score")
public class CreditScoreRecord {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "request_id", nullable = false, unique = true, length = 64)
    private String requestId;

    @Column(name = "loan_id", nullable = false, length = 18)
    private String loanId;

    @Column(nullable = false, precision = 16, scale = 2)
    private BigDecimal amount;

    @Column(name = "term_months", nullable = false)
    private int termMonths;

    @Column(name = "monthly_income", nullable = false, precision = 16, scale = 2)
    private BigDecimal monthlyIncome;

    @Column(length = 40)
    private String purpose;

    @Column(nullable = false)
    private int score;

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.VARCHAR)
    @Column(name = "risk_tier", nullable = false, length = 1)
    private RiskTier riskTier;

    @Column(name = "monthly_payment", nullable = false, precision = 16, scale = 2)
    private BigDecimal monthlyPayment;

    @Column(name = "debt_to_income", nullable = false, precision = 12, scale = 4)
    private BigDecimal debtToIncome;

    @Convert(converter = ReasonsConverter.class)
    @Column(nullable = false, length = 2000)
    private List<String> reasons;

    @Column(name = "model_version", nullable = false, length = 20)
    private String modelVersion;

    @Column(name = "scored_at", nullable = false)
    private Instant scoredAt;

    protected CreditScoreRecord() {

    }

    public CreditScoreRecord(String requestId, String loanId, BigDecimal amount, int termMonths,
                             BigDecimal monthlyIncome, String purpose, int score, RiskTier riskTier,
                             BigDecimal monthlyPayment, BigDecimal debtToIncome, List<String> reasons,
                             String modelVersion, Instant scoredAt) {
        this.requestId = requestId;
        this.loanId = loanId;
        this.amount = amount;
        this.termMonths = termMonths;
        this.monthlyIncome = monthlyIncome;
        this.purpose = purpose;
        this.score = score;
        this.riskTier = riskTier;
        this.monthlyPayment = monthlyPayment;
        this.debtToIncome = debtToIncome;
        this.reasons = reasons;
        this.modelVersion = modelVersion;
        this.scoredAt = scoredAt;
    }

    public UUID getId() { return id; }
    public String getRequestId() { return requestId; }
    public String getLoanId() { return loanId; }
    public BigDecimal getAmount() { return amount; }
    public int getTermMonths() { return termMonths; }
    public BigDecimal getMonthlyIncome() { return monthlyIncome; }
    public String getPurpose() { return purpose; }
    public int getScore() { return score; }
    public RiskTier getRiskTier() { return riskTier; }
    public BigDecimal getMonthlyPayment() { return monthlyPayment; }
    public BigDecimal getDebtToIncome() { return debtToIncome; }
    public List<String> getReasons() { return reasons; }
    public String getModelVersion() { return modelVersion; }
    public Instant getScoredAt() { return scoredAt; }
}
