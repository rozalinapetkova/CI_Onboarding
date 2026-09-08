import com.sap.it.script.v2.api.Message;
import groovy.json.JsonOutput;
import java.io.Reader;
import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;

def Message processData(Message message) {
    def messageLog = messageLogFactory.getMessageLog(message);
    def headers = message.getHeaders();
    def properties = message.getProperties();

    String correlationId = properties.get("correlationId") as String ?: "unknown";
    String errorClass = properties.get("errorClass") as String ?: "unknown";
    String errorMessage = properties.get("errorMessage") as String ?: "";
    String errorClassification = properties.get("errorClassification") as String ?: "unknown";
    String failedAt = properties.get("failedAt") as String ?:
        OffsetDateTime.now().format(DateTimeFormatter.ISO_OFFSET_DATE_TIME);
    String failedRouteId = properties.get("failedRouteId") as String ?: "unknown";
    Integer redeliveryCounter = (properties.get("redeliveryCounter") ?: 0) as Integer;

    String originalEntryPoint = inferEntryPoint(headers);
    String originalBody = "";
    try {
        Reader reader = message.getBody(java.io.Reader);
        if (reader != null) {
            originalBody = reader.text;
        }
    } catch (Exception e) {
        originalBody = "";
        if (messageLog != null) {
            messageLog.addAttachmentAsString("dlq-body-capture-error",
                "could not read body for DLQ: " + e.getMessage(), "text/plain");
        }
    }

    Map<String, String> capturedHeaders = new LinkedHashMap<>();
    headers.each { k, v ->
        if (k != null && shouldCaptureHeader(k.toString())) {
            capturedHeaders.put(k.toString(), v == null ? "" : v.toString());
        }
    }

    Map envelope = [
        envelopeVersion   : "1",
        correlationId     : correlationId,
        failedAt          : failedAt,
        originalEntryPoint: originalEntryPoint,
        originalIflow     : System.getProperty("CamelComponentName", "roi-orderhub"),
        failedRouteId     : failedRouteId,
        redeliveryCounter : redeliveryCounter,
        classification    : errorClassification,
        errorClass        : errorClass,
        errorMessage      : errorMessage,
        originalHeaders   : capturedHeaders,
        originalBody      : originalBody
    ];

    String envelopeJson = JsonOutput.prettyPrint(JsonOutput.toJson(envelope));

    message.setHeader("CamelJmsDestinationName", "roi.orderhub.dlq");
    message.setHeader("dlq.correlationId", correlationId);
    message.setHeader("dlq.classification", errorClassification);
    message.setHeader("dlq.originalEntryPoint", originalEntryPoint);
    message.setProperty("dlqEnvelope", envelopeJson);
    message.setBody(envelopeJson);

    if (messageLog != null) {
        messageLog.setStringProperty("dlqDestination", "roi.orderhub.dlq");
        messageLog.addAttachmentAsString("dlq-envelope", envelopeJson, "application/json");
    }

    return message;
}

String inferEntryPoint(Map headers) {
    if (headers.get("ce-id") != null) {
        return "amqp:" + (headers.get("ce-type") ?: "unknown");
    }
    if (headers.get("CamelHttpUrl") != null || headers.get("CamelHttpMethod") != null) {
        return "http:" + (headers.get("CamelHttpUrl") ?: "");
    }
    if (headers.get("JMSDestination") != null) {
        return "jms:" + headers.get("JMSDestination").toString();
    }
    return "unknown";
}

boolean shouldCaptureHeader(String name) {
    if (name == null) return false;
    String lower = name.toLowerCase();
    if (lower.startsWith("camel")) return false;
    if (lower.startsWith("breadcrumb")) return false;
    if (lower.equals("authorization")) return false;
    if (lower.equals("cookie")) return false;
    return true;
}
