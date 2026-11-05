package com.erez.loans.scoring.api;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

@SpringBootTest(properties = {
        "scoring.api-key=test-key",
        "scoring.simulation.enabled=true",
        "spring.datasource.url=jdbc:h2:mem:scoring;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1",
        "spring.datasource.username=sa",
        "spring.datasource.password="
})
@AutoConfigureMockMvc
class CreditScoreControllerTest {

    private static final String URL = "/api/v1/credit-scores";

    @Autowired
    private MockMvc mvc;

    private static String body(String requestId) {
        return body(requestId, "a0X000000000001");
    }

    private static String body(String requestId, String loanId) {
        return """
            {"requestId":"%s","loanId":"%s","amount":100000,
             "termMonths":60,"monthlyIncome":15000,"purpose":"Personal"}
            """.formatted(requestId, loanId);
    }

    @Test
    void scoresValidRequest() throws Exception {
        mvc.perform(post(URL).header("X-API-Key", "test-key")
                        .contentType(MediaType.APPLICATION_JSON).content(body("req-1")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.requestId").value("req-1"))
                .andExpect(jsonPath("$.loanId").value("a0X000000000001"))
                .andExpect(jsonPath("$.score").isNumber())
                .andExpect(jsonPath("$.riskTier").isString())
                .andExpect(jsonPath("$.modelVersion").value("rules-v1"));
    }

    @Test
    void rejectsMissingApiKey() throws Exception {
        mvc.perform(post(URL).contentType(MediaType.APPLICATION_JSON).content(body("req-2")))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void rejectsWrongApiKey() throws Exception {
        mvc.perform(post(URL).header("X-API-Key", "nope")
                        .contentType(MediaType.APPLICATION_JSON).content(body("req-3")))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void rejectsInvalidBody() throws Exception {
        mvc.perform(post(URL).header("X-API-Key", "test-key")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"requestId\":\"req-4\",\"loanId\":\"x\",\"amount\":-5,\"termMonths\":2}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.status").value(400));
    }

    @Test
    void retryWithSameRequestIdReturnsSameResult() throws Exception {
        MvcResult first = mvc.perform(post(URL).header("X-API-Key", "test-key")
                        .contentType(MediaType.APPLICATION_JSON).content(body("req-5")))
                .andExpect(status().isOk()).andReturn();
        MvcResult second = mvc.perform(post(URL).header("X-API-Key", "test-key")
                        .contentType(MediaType.APPLICATION_JSON).content(body("req-5")))
                .andExpect(status().isOk()).andReturn();

        org.assertj.core.api.Assertions.assertThat(second.getResponse().getContentAsString())
                .isEqualTo(first.getResponse().getContentAsString());
    }

    @Test
    void reusingRequestIdForAnotherLoanIsConflict() throws Exception {
        mvc.perform(post(URL).header("X-API-Key", "test-key")
                        .contentType(MediaType.APPLICATION_JSON).content(body("req-7", "a0X000000000007")))
                .andExpect(status().isOk());
        mvc.perform(post(URL).header("X-API-Key", "test-key")
                        .contentType(MediaType.APPLICATION_JSON).content(body("req-7", "a0X000000000008")))
                .andExpect(status().isConflict());
    }

    @Test
    void historyReturnsAllScoresForLoanNewestFirst() throws Exception {
        String loanId = "a0X000000000009";
        for (String requestId : new String[]{"req-9a", "req-9b"}) {
            mvc.perform(post(URL).header("X-API-Key", "test-key")
                            .contentType(MediaType.APPLICATION_JSON).content(body(requestId, loanId)))
                    .andExpect(status().isOk());
        }

        mvc.perform(get(URL).param("loanId", loanId).header("X-API-Key", "test-key"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(2))
                .andExpect(jsonPath("$[0].requestId").value("req-9b"));
    }

    @Test
    void simulatedOutageReturns503() throws Exception {
        mvc.perform(post(URL).header("X-API-Key", "test-key").header("X-Simulate", "error")
                        .contentType(MediaType.APPLICATION_JSON).content(body("req-6")))
                .andExpect(status().isServiceUnavailable());
    }

    @Test
    void healthIsOpenWithoutApiKey() throws Exception {
        mvc.perform(get("/actuator/health"))
                .andExpect(status().isOk());
    }
}
