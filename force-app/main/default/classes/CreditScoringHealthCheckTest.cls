/**
 * Created by doritpessler on 06/11/2026.
 */

@IsTest
private with sharing class CreditScoringHealthCheckTest {

    private class HealthMock implements System.HttpCalloutMock {
        Integer statusCode;
        String body;
        Boolean throwError = false;
        HttpRequest received;

        HealthMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest request) {
            received = request;
            if (throwError) {
                throw new CalloutException('Unable to tunnel through proxy');
            }
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(body);
            return response;
        }
    }

    @IsTest
    static void reportsUpWhenServiceIsHealthy() {
        HealthMock mock = new HealthMock(200, '{"status":"UP"}');
        Test.setMock(System.HttpCalloutMock.class, mock);

        Test.startTest();
        CreditScoringHealthCheck.Status status = CreditScoringHealthCheck.check();
        Test.stopTest();

        Assert.isTrue(status.up);
        Assert.areEqual(200, status.statusCode);
        Assert.isNull(status.errorMessage);
        Assert.areEqual(CreditScoringHealthCheck.ENDPOINT, mock.received.getEndpoint());
        Assert.areEqual('GET', mock.received.getMethod());
    }

    @IsTest
    static void reportsDownOnServerError() {
        Test.setMock(System.HttpCalloutMock.class, new HealthMock(503, '{"status":"DOWN"}'));

        Test.startTest();
        CreditScoringHealthCheck.Status status = CreditScoringHealthCheck.check();
        Test.stopTest();

        Assert.isFalse(status.up);
        Assert.areEqual(503, status.statusCode);
        Assert.isTrue(status.errorMessage.contains('HTTP 503'), status.errorMessage);
    }

    @IsTest
    static void reportsDownWhenPathIsWrong() {
        // The 404 we saw when the Named Credential URL included a path
        Test.setMock(System.HttpCalloutMock.class,
                new HealthMock(404, '{"status":404,"instance":"/api/v1/credit-scores/actuator/health"}'));

        Test.startTest();
        CreditScoringHealthCheck.Status status = CreditScoringHealthCheck.check();
        Test.stopTest();

        Assert.isFalse(status.up);
        Assert.areEqual(404, status.statusCode);
    }

    @IsTest
    static void reportsDownOnNonJsonBody() {
        Test.setMock(System.HttpCalloutMock.class, new HealthMock(200, '<html>not the service</html>'));

        Test.startTest();
        CreditScoringHealthCheck.Status status = CreditScoringHealthCheck.check();
        Test.stopTest();

        Assert.isFalse(status.up);
    }

    @IsTest
    static void reportsDownWhenCalloutFails() {
        HealthMock mock = new HealthMock(200, '');
        mock.throwError = true;
        Test.setMock(System.HttpCalloutMock.class, mock);

        Test.startTest();
        CreditScoringHealthCheck.Status status = CreditScoringHealthCheck.check();
        Test.stopTest();

        Assert.isFalse(status.up);
        Assert.isNull(status.statusCode);
        Assert.isTrue(status.errorMessage.contains('Unable to tunnel'), status.errorMessage);
    }

}