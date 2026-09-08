import com.sap.it.script.v2.api.Message;
import groovy.json.JsonSlurper;
import groovy.json.JsonOutput;
import java.io.Reader;

// Merge the restcountries response (current body) with the original customer
// request (parked in property "CustomerRequest" by the upstream Content Modifier).
// Runs after the HTTP receiver call to restcountries.

def Message processData(Message message) {
    def messageLog = messageLogFactory?.createMessageLog(message);

    Reader reader = message.getBody(java.io.Reader);
    def upstream = null;
    try {
        upstream = new JsonSlurper().parse(reader);
    } catch (Exception parseErr) {
        // 404 from restcountries returns "Not Found" plain text — slurper fails.
        upstream = null;
    }

    def customerJson = message.getProperty("CustomerRequest");
    def customer = new JsonSlurper().parseText(customerJson as String);

    def countryBlock;
    String lookupStatus;

    if (upstream && upstream instanceof List && !upstream.isEmpty()) {
        def c = upstream[0];
        def currencyCode = (c.currencies instanceof Map && !c.currencies.isEmpty())
                ? c.currencies.keySet().iterator().next()
                : null;
        countryBlock = [
                code     : c.cca2,
                name     : c.name?.common,
                capital  : (c.capital instanceof List && !c.capital.isEmpty()) ? c.capital[0] : null,
                region   : c.region,
                currency : currencyCode
        ];
        lookupStatus = "ok";
    } else {
        countryBlock = [
                code     : customer.country,
                name     : null,
                capital  : null,
                region   : null,
                currency : null
        ];
        lookupStatus = "not_found";
        messageLog?.addAttachmentAsString(
                "restcountries-miss",
                "country code ${customer.country} not resolved",
                "text/plain");
    }

    def merged = [
            customerId   : customer.customerId,
            name         : customer.name,
            country      : countryBlock,
            lookupStatus : lookupStatus
    ];

    message.setHeader("Content-Type", "application/json");
    message.setBody(JsonOutput.prettyPrint(JsonOutput.toJson(merged)));
    return message;
}
