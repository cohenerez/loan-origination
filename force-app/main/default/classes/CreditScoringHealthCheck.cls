/**
* Checks that Salesforce can reach the credit scoring service through the Credit_Scoring Named Credential.
 * Use from Anonymous Apex:  System.debug(CreditScoringHealthCheck.check());
 */

public with sharing class CreditScoringHealthCheck {

    public static final String ENDPOINT = 'callout:Credit_Scoring/actuator/health';
    public static final Integer TIMEOUT_MS = 10000;

    public class Status {
        @AuraEnabled public Boolean up = false;
        @AuraEnabled public Integer statusCode;
        @AuraEnabled public String body;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public Integer elapsedMs;
    }

    @AuraEnabled
    public static Status check() {
        Status status = new Status();
        HttpRequest request = new HttpRequest();
        request.setEndpoint(ENDPOINT);
        request.setMethod('GET');
        request.setTimeout(TIMEOUT_MS);

        Long started = System.currentTimeMillis();
        try {
            HttpResponse response = new Http().send(request);
            status.statusCode = response.getStatusCode();
            status.body = response.getBody();
            status.up = status.statusCode == 200 && reportsUp(status.body);
            if (!status.up) {
                status.errorMessage = 'Unexpected response: HTTP ' + status.statusCode;
            }
        } catch (CalloutException e) {
            status.errorMessage = e.getMessage();
        }
        status.elapsedMs = (System.currentTimeMillis() - started).intValue();

        System.debug(LoggingLevel.INFO, 'Credit scoring health: up=' + status.up
                + ' status=' + status.statusCode + ' time=' + status.elapsedMs + 'ms'
                + (status.errorMessage == null ? '' : ' error=' + status.errorMessage));
        return status;
    }

    private static Boolean reportsUp(String body) {
        try {
            Map<String, Object> json = (Map<String, Object>) JSON.deserializeUntyped(body);
            return json.get('status') == 'UP';
        } catch (Exception e) {
            return false;
        }
    }

}