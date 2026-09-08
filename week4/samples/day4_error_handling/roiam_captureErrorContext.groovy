import com.sap.it.script.v2.api.Message;
import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;

def Message processData(Message message) {
    def messageLog = messageLogFactory.getMessageLog(message);
    def headers = message.getHeaders();
    def properties = message.getProperties();

    Throwable cause = (Throwable) properties.get("CamelExceptionCaught");
    String failedRouteId = properties.get("CamelFailureRouteId") as String;
    String failedEndpoint = properties.get("CamelFailureEndpoint") as String;
    Integer redeliveryCounter = (properties.get("CamelRedeliveryCounter") ?: 0) as Integer;

    String errorClass = cause != null ? cause.getClass().getName() : "unknown";
    String errorMessage = cause != null ? (cause.getMessage() ?: "") : "no exception attached";
    String errorClassification = classify(cause);
    String failedAt = OffsetDateTime.now().format(DateTimeFormatter.ISO_OFFSET_DATE_TIME);

    String correlationId = headers.get("correlationId") as String;
    if (correlationId == null || correlationId.trim().isEmpty()) {
        correlationId = headers.get("ce-id") as String;
    }
    if (correlationId == null || correlationId.trim().isEmpty()) {
        correlationId = UUID.randomUUID().toString();
    }

    message.setProperty("errorClass", errorClass);
    message.setProperty("errorMessage", errorMessage);
    message.setProperty("errorClassification", errorClassification);
    message.setProperty("failedAt", failedAt);
    message.setProperty("failedRouteId", failedRouteId ?: "unknown");
    message.setProperty("failedEndpoint", failedEndpoint ?: "");
    message.setProperty("redeliveryCounter", redeliveryCounter);
    message.setProperty("correlationId", correlationId);

    if (messageLog != null) {
        messageLog.setStringProperty("errorClassification", errorClassification);
        messageLog.setStringProperty("errorClass", errorClass);

        // Deliberately setStringProperty here, not addCustomHeaderProperty. correlationId is
        // already registered as a message-wide searchable property earlier in the flow, by
        // whichever step first accepted or generated it - we don't want to register it again
        // here. What we do want is for it to show up alongside this step's own error
        // diagnostics, so it reads as one block when someone opens this specific step's
        // Properties subsection at Debug or Trace level. setStringProperty gives us exactly
        // that: step-local visibility, not a second, redundant message-wide registration.
        messageLog.setStringProperty("correlationId", correlationId);
        messageLog.setStringProperty("failedRouteId", failedRouteId ?: "unknown");
        messageLog.setStringProperty("redeliveryCounter", redeliveryCounter as String);

        StringBuilder context = new StringBuilder();
        context.append("correlationId=").append(correlationId).append('\n');
        context.append("failedAt=").append(failedAt).append('\n');
        context.append("failedRouteId=").append(failedRouteId ?: "unknown").append('\n');
        context.append("failedEndpoint=").append(failedEndpoint ?: "").append('\n');
        context.append("redeliveryCounter=").append(redeliveryCounter).append('\n');
        context.append("errorClassification=").append(errorClassification).append('\n');
        context.append("errorClass=").append(errorClass).append('\n');
        context.append("errorMessage=").append(errorMessage).append('\n');
        if (cause != null) {
            context.append("stackTrace=\n");
            StringWriter sw = new StringWriter();
            cause.printStackTrace(new PrintWriter(sw));
            context.append(sw.toString());
        }
        messageLog.addAttachmentAsString("error-context", context.toString(), "text/plain");

        try {
            String capturedBody = message.getBody(String) ?: "";
            messageLog.addAttachmentAsString("failed-payload", capturedBody, "text/plain");
        } catch (Exception bodyEx) {
            messageLog.addAttachmentAsString("failed-payload-error",
                "could not capture body: " + bodyEx.getMessage(), "text/plain");
        }
    }

    return message;
}

String classify(Throwable cause) {
    if (cause == null) {
        return "unknown";
    }
    String name = cause.getClass().getName();
    String msg = (cause.getMessage() ?: "").toLowerCase();

    if (name.contains("JsonException") || name.contains("XmlException") ||
        name.contains("SAXParseException") || name.contains("MarshalException")) {
        return "poison";
    }
    if (name.contains("ConnectException") || name.contains("SocketTimeout") ||
        name.contains("UnknownHostException") || name.contains("NoRouteToHostException")) {
        return "transient";
    }
    if (name.contains("PartnerDirectory") || name.contains("SecurityMaterial") ||
        msg.contains("parameter not found") || msg.contains("alias not found")) {
        return "configuration";
    }
    if (msg.contains("credit hold") || msg.contains("sku not orderable") ||
        msg.contains("duplicate orderid")) {
        return "business";
    }
    if (name.contains("OutOfMemoryError") || name.contains("StackOverflowError")) {
        return "runtime";
    }
    return "unknown";
}
