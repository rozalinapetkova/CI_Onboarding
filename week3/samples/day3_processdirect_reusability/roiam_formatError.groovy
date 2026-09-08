import com.sap.it.script.v2.api.Message;
import groovy.json.JsonOutput;

// Build a canonical error JSON envelope. Use in the Exception Subprocess of any iFlow
// that needs a consistent error shape for downstream alerting / DLQ replay tools.
// Lives in sc_<initials>_OrderHubHelpers.
//
// Output shape (insertion order preserved by LinkedHashMap + JsonOutput):
// {
//   "status": "failed",
//   "category": "Retry" | "Bypass" | "Unknown",
//   "correlationId": "...",
//   "orderId": "...",
//   "error": "human-readable message",
//   "exceptionClass": "java.net.ConnectException"
// }

def Message processData(Message message) {
    def headers = message.getHeaders();
    def properties = message.getProperties();

    Object exObj = properties.get("CamelExceptionCaught");
    String exMessage = "Unknown error";
    String exClass = "";
    if (exObj != null) {
        if (exObj instanceof Throwable) {
            exMessage = ((Throwable) exObj).getMessage() ?: "Unknown error";
        }
        exClass = exObj.getClass().getName();
    }

    String correlationId = headers.get("correlationId") as String;
    String orderId       = headers.get("orderId") as String;
    String category      = (properties.get("errorCategory") ?: "Unknown") as String;

    Map<String,Object> err = new LinkedHashMap<>(6);
    err.put("status", "failed");
    err.put("category", category);
    err.put("correlationId", correlationId);
    err.put("orderId", orderId);
    err.put("error", exMessage);
    err.put("exceptionClass", exClass);

    String body = JsonOutput.toJson(err);

    def messageLog = messageLogFactory.getMessageLog(message);
    if (messageLog != null) {
        messageLog.setStringProperty("errorCategory", category);
        messageLog.setStringProperty("exceptionClass", exClass);
        messageLog.addAttachmentAsString("error-context", body, "application/json");
    }

    message.setHeader("Content-Type", "application/json");
    message.setBody(body);
    return message;
}
