import com.sap.it.script.v2.api.Message;
import java.io.Reader;

// Log the incoming message and attach the full body to the MPL.
// Lives in sc_<initials>_OrderHubHelpers; referenced by both the producer and consumer iFlows.
//
// Deliberate exception to the streaming rule: this script materializes the body to a String
// because attaching to the MPL is the explicit goal. Downstream steps see the body as String,
// which is fine for canonical-XML/JSON-sized payloads in the Order Hub flow.

def Message processData(Message message) {
    def headers = message.getHeaders();

    String correlationId = headers.get("correlationId") as String;
    String orderId       = headers.get("orderId") as String;
    String orderFormat   = headers.get("X-Order-Format") as String;

    Reader reader = message.getBody(java.io.Reader);
    StringBuilder sb = new StringBuilder(4096);
    char[] buf = new char[4096];
    int n;
    while ((n = reader.read(buf)) != -1) {
        sb.append(buf, 0, n);
    }
    String bodyString = sb.toString();

    String contentType = (headers.get("Content-Type") ?: "application/octet-stream") as String;

    def messageLog = messageLogFactory.getMessageLog(message);
    if (messageLog != null) {
        if (correlationId != null) {
            messageLog.addCustomHeaderProperty("correlationId", correlationId);
        }
        if (orderId != null) {
            messageLog.addCustomHeaderProperty("orderId", orderId);
        }
        if (orderFormat != null) {
            messageLog.setStringProperty("orderFormat", orderFormat);
        }
        messageLog.addAttachmentAsString("incoming", bodyString, contentType);
    }

    message.setBody(bodyString);
    return message;
}
