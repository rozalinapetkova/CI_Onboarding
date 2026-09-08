import com.sap.it.script.v2.api.Message;
import groovy.json.JsonOutput;
import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;

def Message processData(Message message) {
    def messageLog = messageLogFactory.createMessageLog(message);
    def properties = message.getProperties();

    String correlationId = properties.get("correlationId") as String ?: "unknown";
    String errorClassification = properties.get("errorClassification") as String ?: "unknown";
    String errorClass = properties.get("errorClass") as String ?: "unknown";
    String errorMessage = properties.get("errorMessage") as String ?: "";
    String failedRouteId = properties.get("failedRouteId") as String ?: "unknown";
    String failedAt = properties.get("failedAt") as String ?:
        OffsetDateTime.now().format(DateTimeFormatter.ISO_OFFSET_DATE_TIME);

    String alertCategory = pickCategory(errorClassification);
    String severity = pickSeverity(errorClassification);
    String subject = "[" + severity + "] " + alertCategory + " — " + errorClass;

    if (subject.length() > 120) {
        subject = subject.substring(0, 117) + "...";
    }

    Map alertEvent = [
        type           : alertCategory,
        eventTimestamp : failedAt,
        subject        : subject,
        severity       : severity,
        category       : "EXCEPTION",
        body           : truncate(errorMessage, 1024),
        tags           : [
            correlationId  : correlationId,
            classification : errorClassification,
            failedRouteId  : failedRouteId,
            iflow          : "roi-orderhub"
        ]
    ];

    String alertJson = JsonOutput.toJson(alertEvent);

    message.setHeader("Content-Type", "application/json");
    message.setProperty("alertCategory", alertCategory);
    message.setProperty("alertSeverity", severity);
    message.setBody(alertJson);

    if (messageLog != null) {
        messageLog.setStringProperty("alertCategory", alertCategory);
        messageLog.setStringProperty("alertSeverity", severity);
        messageLog.addAttachmentAsString("alert-event", alertJson, "application/json");
    }

    return message;
}

String pickCategory(String classification) {
    switch (classification) {
        case "configuration": return "roi.orderhub.dlq";
        case "poison":        return "roi.orderhub.dlq";
        case "transient":     return "roi.orderhub.retry-stuck";
        case "runtime":       return "roi.orderhub.dlq";
        case "business":      return "roi.orderhub.business-reject";
        default:              return "roi.orderhub.dlq";
    }
}

String pickSeverity(String classification) {
    switch (classification) {
        case "configuration": return "ERROR";
        case "poison":        return "ERROR";
        case "runtime":       return "ERROR";
        case "transient":     return "WARNING";
        case "business":      return "INFO";
        default:              return "ERROR";
    }
}

String truncate(String value, int max) {
    if (value == null) return "";
    if (value.length() <= max) return value;
    return value.substring(0, max - 3) + "...";
}
