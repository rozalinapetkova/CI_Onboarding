import com.sap.it.script.v2.api.Message;
import groovy.json.JsonOutput;

// Builds the response envelope that gets cached in the Data Store and
// returned to the caller. Place this script AFTER ProcessDirect succeeds
// and BEFORE the Data Store Write step.
//
// Source of values:
//   header X-Order-Sequence  → set by the Number Range step
//   header orderId           → set by the inbound Content Modifier
//   header correlationId     → set by the inbound Content Modifier
//
// The script:
//   1. Snapshots the current body (canonical XML from the translator)
//      to property `canonicalOrderXml` so JMS can still publish it later.
//   2. Replaces the body with a JSON envelope for the Data Store Write
//      and the eventual 202 response body.
//
// After the Data Store Write step, a Content Modifier restores the body
// from `property.canonicalOrderXml` so JMS publishes the XML.

def Message processData(Message message) {
    def headers = message.getHeaders();
    Reader reader = message.getBody(java.io.Reader);
    StringBuilder sb = new StringBuilder(4096);
    char[] buf = new char[4096];
    int n;
    while ((n = reader.read(buf)) > 0) sb.append(buf, 0, n);
    String canonicalXml = sb.toString();
    message.setProperty("canonicalOrderXml", canonicalXml);

    String orderSequence = headers.get("X-Order-Sequence") as String;
    String orderId = headers.get("orderId") as String;
    String correlationId = headers.get("correlationId") as String;

    Map<String, Object> envelope = new LinkedHashMap<>(4);
    envelope.put("status", "accepted");
    if (orderSequence != null) envelope.put("orderSequence", orderSequence);
    if (orderId != null) envelope.put("orderId", orderId);
    if (correlationId != null) envelope.put("correlationId", correlationId);

    String envelopeJson = JsonOutput.toJson(envelope);
    message.setBody(envelopeJson);
    message.setHeader("Content-Type", "application/json");
    message.setProperty("responseEnvelope", envelopeJson);

    def messageLog = messageLogFactory.getMessageLog(message);
    if (messageLog != null) {
        messageLog.setStringProperty("orderSequence", orderSequence ?: "n/a");
        messageLog.addCustomHeaderProperty("orderId", orderId ?: "n/a");
        messageLog.addAttachmentAsString("response-envelope",
            JsonOutput.prettyPrint(envelopeJson), "application/json");
    }
    return message;
}
