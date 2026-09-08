import com.sap.it.script.v2.api.Message;
import groovy.json.JsonOutput;

// Rejects calls missing the X-Idempotency-Key header with HTTP 400.
//
// Place this script as the FIRST step in roi_<initials>_OrderHub, immediately
// after the HTTPS sender. If the header is present, the script is a no-op and
// processing continues normally. If absent, the script rewrites the body to an
// error envelope, sets the CamelHttpResponseCode to 400, and sets a property
// rejectAtSender=true. A Router after this script branches on the property:
//
//   ${property.rejectAtSender} = 'true'  → End (returns the 400 to the caller)
//   default                              → roiam_logIncoming → Data Store Get → ...

def Message processData(Message message) {
    def headers = message.getHeaders();
    String idempKey = headers.get("X-Idempotency-Key") as String;

    if (idempKey != null && !idempKey.trim().isEmpty()) {
        message.setProperty("rejectAtSender", "false");
        return message;
    }

    String correlationId = headers.get("correlationId") as String;
    Map<String, Object> err = new LinkedHashMap<>(3);
    err.put("error", "X-Idempotency-Key header required");
    err.put("hint", "Generate a UUID per business intent and send it as X-Idempotency-Key. Retries with the same key are de-duplicated.");
    if (correlationId != null) err.put("correlationId", correlationId);

    message.setBody(JsonOutput.toJson(err));
    message.setHeader("Content-Type", "application/json");
    message.setHeader("CamelHttpResponseCode", 400);
    message.setProperty("rejectAtSender", "true");

    def messageLog = messageLogFactory.createMessageLog(message);
    if (messageLog != null) {
        messageLog.setStringProperty("rejectionReason", "missing X-Idempotency-Key");
        messageLog.addAttachmentAsString("rejection", JsonOutput.prettyPrint(JsonOutput.toJson(err)), "application/json");
    }
    return message;
}
