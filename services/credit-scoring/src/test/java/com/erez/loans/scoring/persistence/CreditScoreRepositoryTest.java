package com.erez.loans.scoring.persistence;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.erez.loans.scoring.engine.RiskTier;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.dao.DataIntegrityViolationException;

/** Runs the Flyway migration on an embedded database and checks the JPA mapping against it. */
@DataJpaTest
class CreditScoreRepositoryTest {

    @Autowired
    private CreditScoreRepository repository;

    private static CreditScoreRecord record(String requestId, String loanId, Instant scoredAt) {
        return new CreditScoreRecord(requestId, loanId, new BigDecimal("100000.00"), 60,
                new BigDecimal("15000.00"), "Personal", 712, RiskTier.B,
                new BigDecimal("1933.28"), new BigDecimal("0.1289"),
                List.of("Low payment-to-income ratio", "Second reason"), "rules-v1", scoredAt);
    }

    @Test
    void savesAndFindsByRequestId() {
        repository.saveAndFlush(record("r-1", "a0X1", Instant.parse("2026-11-04T10:00:00Z")));

        CreditScoreRecord found = repository.findByRequestId("r-1").orElseThrow();

        assertThat(found.getId()).isNotNull();
        assertThat(found.getRiskTier()).isEqualTo(RiskTier.B);
        assertThat(found.getReasons()).containsExactly("Low payment-to-income ratio", "Second reason");
    }

    @Test
    void historyIsNewestFirst() {
        repository.save(record("r-2", "a0X2", Instant.parse("2026-11-04T10:00:00Z")));
        repository.save(record("r-3", "a0X2", Instant.parse("2026-11-04T11:00:00Z")));
        repository.flush();

        assertThat(repository.findByLoanIdOrderByScoredAtDesc("a0X2"))
                .extracting(CreditScoreRecord::getRequestId)
                .containsExactly("r-3", "r-2");
    }

    @Test
    void requestIdIsUnique() {
        repository.saveAndFlush(record("r-4", "a0X4", Instant.now()));

        assertThatThrownBy(() -> repository.saveAndFlush(record("r-4", "a0X4", Instant.now())))
                .isInstanceOf(DataIntegrityViolationException.class);
    }
}
