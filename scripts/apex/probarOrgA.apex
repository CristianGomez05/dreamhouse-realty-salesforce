try {
    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:OrgA_Cierre/services/data/v67.0/query?q=SELECT+Id+FROM+Propiedad__c+LIMIT+1');
    req.setMethod('GET');
    HttpResponse res = new Http().send(req);
    System.debug('STATUS: ' + res.getStatusCode());
    System.debug('BODY: ' + res.getBody().left(200));
} catch (Exception e) {
    System.debug('ERROR: ' + e.getMessage());
}