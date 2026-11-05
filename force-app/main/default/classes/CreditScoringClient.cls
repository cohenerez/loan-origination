/**
 * HTTP client for the external credit scoring service.
 * The endpoint and the API key come from the Credit_Scoring Named Credential, never from code.
 * Never throws for remote failures: every outcome is returned as a Result so the caller can record it.
 */

public with sharing class CreditScoringClient {

    public static final String ENDPOINT = 'callout:Credit_Scoring/api/v1/credit-scores';
    public static final Integer TIMEOUT_MS = 10000;

    public static final String SUCCESS = 'Success';
    public static final String FAILED  = 'Failed';
    public static final String TIMEOUT = 'Timeout';

    public class ScoreRequest {
        public String requestId;
        public String loanId;
        public Decimal amount;
        public Integer termMonths;
        public Decimal monthlyIncome;
        public String purpose;
    }

    public class ScoreResponse {
        public String requestId;
        public String loanId;
        public Integer score;
        public String riskTier;
        public Decimal monthlyPayment;
        public Decimal debtToIncome;
        public List<String> reasons;
        public String modelVersion;
    }

    public class Result {
        public String requestId;
        public String outcome;
        public Integer statusCode;
        public ScoreResponse response;
        public String errorMessage;
        public String rawBody;
        public Integer elapsedMs;

        public Boolean isSuccess() {
            return outcome == SUCCESS;
        }
    }

    public Result score(ScoreRequest request) {
        Result result = new Result();
        result.requestId = request.requestId;

        HttpRequest http = new HttpRequest();
        http.setEndpoint(ENDPOINT);
        http.setMethod('POST');
        http.setHeader('Content-Type', 'application/json');
        http.setHeader('Accept', 'application/json');
        http.setTimeout(TIMEOUT_MS);
        http.setBody(JSON.serialize(request, true));

        Long started = System.currentTimeMillis();
        try {
            HttpResponse response = new Http().send(http);
            result.elapsedMs = elapsedSince(started);
            result.statusCode = response.getStatusCode();
            result.rawBody = response.getBody();

            if (result.statusCode != 200) {
                return fail(result, FAILED, 'HTTP ' + result.statusCode + ' ' + response.getStatus());
            }
            try {
                result.response = (ScoreResponse) JSON.deserialize(result.rawBody, ScoreResponse.class);
            } catch (JSONException e) {
                return fail(result, FAILED, 'Invalid response body: ' + e.getMessage());
            }
            if (result.response == null || result.response.score == null || String.isBlank(result.response.riskTier)) {
                return fail(result, FAILED, 'Response is missing score or riskTier');
            }
            result.outcome = SUCCESS;
        } catch (CalloutException e) {
            result.elapsedMs = elapsedSince(started);
            String message = e.getMessage();
            Boolean timedOut = message != null && message.containsIgnoreCase('timed out');
            fail(result, timedOut ? TIMEOUT : FAILED, message);
        }
        return result;
    }

     // A failed result for a request that was never sent, e.g. missing input.
    public static Result notSent(String requestId, String reason) {
        Result result = new Result();
        result.requestId = requestId;
        result.elapsedMs = 0;
        return fail(result, FAILED, reason);
    }

    private static Result fail(Result result, String outcome, String message) {
        result.outcome = outcome;
        result.errorMessage = message;
        return result;
    }

    private static Integer elapsedSince(Long started) {
        return (System.currentTimeMillis() - started).intValue();
    }

}