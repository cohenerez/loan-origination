package com.erez.loans.scoring.api;

import com.erez.loans.scoring.engine.LoanFacts;
import com.erez.loans.scoring.engine.ScoringEngine;
import com.erez.loans.scoring.engine.ScoringResult;
import com.erez.loans.scoring.persistence.CreditScoreRecord;
import com.erez.loans.scoring.persistence.CreditScoreRepository;
import java.time.Clock;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;


@Service
public class CreditScoreService {

    static final String MODEL_VERSION = "rules-v1";

    private final ScoringEngine engine;
    private final CreditScoreRepository repository;
    private final Clock clock;

    public CreditScoreService(ScoringEngine engine, CreditScoreRepository repository, Clock clock) {
        this.engine = engine;
        this.repository = repository;
        this.clock = clock;
    }

    public CreditScoreResponse score(CreditScoreRequest request) {
        return repository.findByRequestId(request.requestId())
                .map(existing -> replay(existing, request))
                .orElseGet(() -> scoreAndStore(request));
    }

    public List<CreditScoreResponse> history(String loanId) {
        return repository.findByLoanIdOrderByScoredAtDesc(loanId).stream()
                .map(CreditScoreService::toResponse)
                .toList();
    }

    private CreditScoreResponse scoreAndStore(CreditScoreRequest request) {
        ScoringResult result = engine.score(new LoanFacts(
                request.loanId(), request.amount(), request.termMonths(),
                request.monthlyIncome(), request.purpose()));

        CreditScoreRecord record = new CreditScoreRecord(
                request.requestId(), request.loanId(), request.amount(), request.termMonths(),
                request.monthlyIncome(), request.purpose(), result.score(), result.riskTier(),
                result.monthlyPayment(), result.debtToIncome(), result.reasons(), MODEL_VERSION,
                // Database timestamps keep microseconds; truncating keeps replays byte-identical
                Instant.now(clock).truncatedTo(ChronoUnit.MICROS));
        try {
            return toResponse(repository.saveAndFlush(record));
        } catch (DataIntegrityViolationException e) {
            // A concurrent retry with the same requestId inserted first; return its result
            return repository.findByRequestId(request.requestId())
                    .map(existing -> replay(existing, request))
                    .orElseThrow(() -> e);
        }
    }

    private static CreditScoreResponse replay(CreditScoreRecord existing, CreditScoreRequest request) {
        if (!existing.getLoanId().equals(request.loanId())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "requestId " + request.requestId() + " was already used for a different loan");
        }
        return toResponse(existing);
    }

    private static CreditScoreResponse toResponse(CreditScoreRecord r) {
        return new CreditScoreResponse(r.getRequestId(), r.getLoanId(), r.getScore(), r.getRiskTier(),
                r.getMonthlyPayment(), r.getDebtToIncome(), r.getReasons(), r.getModelVersion(), r.getScoredAt());
    }
}
