package com.erez.loans.scoring.persistence;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface CreditScoreRepository extends JpaRepository<CreditScoreRecord, UUID> {

    Optional<CreditScoreRecord> findByRequestId(String requestId);

    List<CreditScoreRecord> findByLoanIdOrderByScoredAtDesc(String loanId);
}
