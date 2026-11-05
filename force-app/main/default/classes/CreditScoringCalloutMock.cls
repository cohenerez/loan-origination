/**
 * Configurable stand-in for the credit scoring service in tests.
 * By default returns 200 with the configured score and tier, echoing the requestId and loanId it received.
 */
@IsTest
public class CreditScoringCalloutMock implements System.HttpCalloutMock {

    public Integer statusCode = 200;
    public Integer score = 700;
    public String riskTier = 'B';
    public String rawBody;
    public Boolean throwTimeout = false;

    public List<HttpRequest> requests = new List<HttpRequest>();

    public HttpResponse respond(HttpRequest request) {
        requests.add(request);
        if (throwTimeout) {
            throw new CalloutException('Read timed out');
        }

        HttpResponse response = new HttpResponse();
        response.setStatusCode(statusCode);
        response.setStatus(statusCode == 200 ? 'OK' : 'Service Unavailable');
        response.setHeader('Content-Type', 'application/json');

        if (rawBody != null) {
            response.setBody(rawBody);
        } else if (statusCode != 200) {
            response.setBody('{"status":' + statusCode + ',"title":"Service Unavailable"}');
        } else {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
            response.setBody(JSON.serialize(new Map<String, Object>{
                    'requestId' => body.get('requestId'),
                    'loanId' => body.get('loanId'),
                    'score' => score,
                    'riskTier' => riskTier,
                    'monthlyPayment' => 1933.28,
                    'debtToIncome' => 0.1289,
                    'reasons' => new List<String>{ 'Test reason' },
                    'modelVersion' => 'rules-v1',
                    'scoredAt' => '2026-11-05T10:00:00Z'
            }));
        }
        return response;
    }
}