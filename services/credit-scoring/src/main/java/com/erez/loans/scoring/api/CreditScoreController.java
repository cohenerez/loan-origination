package com.erez.loans.scoring.api;

import com.erez.loans.scoring.config.ScoringProperties;
import jakarta.validation.Valid;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/v1/credit-scores")
public class CreditScoreController {

    static final String SIMULATE_HEADER = "X-Simulate";
    private static final Logger log = LoggerFactory.getLogger(CreditScoreController.class);

    private final CreditScoreService service;
    private final ScoringProperties.Simulation simulation;

    public CreditScoreController(CreditScoreService service, ScoringProperties properties) {
        this.service = service;
        this.simulation = properties.simulation();
    }

    @PostMapping
    public CreditScoreResponse score(@Valid @RequestBody CreditScoreRequest request,@RequestHeader(value = SIMULATE_HEADER, required = false) String simulate) throws InterruptedException {

        applySimulation(simulate);
        CreditScoreResponse response = service.score(request);
        log.info("Scored loan {} (request {}): score={} tier={}",
                response.loanId(), response.requestId(), response.score(), response.riskTier());
        return response;
    }


    @GetMapping
    public List<CreditScoreResponse> history(@RequestParam String loanId) {

        return service.history(loanId);
    }


    private void applySimulation(String simulate) throws InterruptedException {
        if (!simulation.enabled() || simulate == null) {
            return;
        }
        switch (simulate.toLowerCase()) {
            case "error" -> throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Simulated outage");
            case "slow" -> Thread.sleep(simulation.slowDelay());
            default -> { }
        }
    }
}
