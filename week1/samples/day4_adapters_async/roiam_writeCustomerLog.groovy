import com.sap.it.script.v2.api.Message;
import groovy.json.JsonSlurper;
import groovy.json.JsonOutput;
import java.io.Reader;

// Build the Data Store entry from the incoming body (the merged customer payload
// from the main iFlow). Adds wallclock + correlationId from the header.
// Runs at the start of roi_<initials>_CustomerLogger, before the Data Store Write step.

def Message processData(Message message) {
    def messageLog = messageLogFactory?.getMessageLog(message);

    Reader reader = message.getBody(java.io.Reader);
    def merged = new JsonSlurper().parse(reader);

    def headers = message.getHeaders();
    String correlationId = headers["correlationId"] ?: headers["SAP_MessageProcessingLogID"] ?: "unknown";
    String customerId = headers["customerId"] ?: merged?.customerId ?: "unknown";

    def entry = [
            schema       : "customer-echo-log/v1",
            recordedAt   : new Date().format("yyyy-MM-dd'T'HH:mm:ss.SSSXXX"),
            correlationId: correlationId,
            customerId   : customerId,
            customer     : merged
    ];

    message.setHeader("customerId", customerId);
    message.setBody(JsonOutput.toJson(entry));

    messageLog?.addAttachmentAsString(
            "customer-echo-log-entry",
            JsonOutput.prettyPrint(JsonOutput.toJson(entry)),
            "application/json");
    return message;
}
