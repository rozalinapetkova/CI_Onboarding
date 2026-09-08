import com.sap.it.script.v2.api.Message;
import java.io.Reader;
import java.util.UUID;

def Message processData(Message message) {
    def headers = message.getHeaders();

    String correlationId = headers.get("correlationId") as String;
    String source = "header.correlationId";

    if (correlationId == null || correlationId.trim().isEmpty()) {
        correlationId = headers.get("ce-id") as String;
        source = "header.ce-id";
    }

    if (correlationId == null || correlationId.trim().isEmpty()) {
        correlationId = UUID.randomUUID().toString();
        source = "generated";
    }

    message.setHeader("correlationId", correlationId);
    message.setProperty("correlationId", correlationId);

    String eventId = headers.get("ce-id") as String;
    String eventType = headers.get("ce-type") as String;
    String eventSource = headers.get("ce-source") as String;
    String eventSubject = headers.get("ce-subject") as String;

    def messageLog = messageLogFactory.getMessageLog(message);
    if (messageLog != null) {
        messageLog.addCustomHeaderProperty("correlationId", correlationId);
        messageLog.setStringProperty("correlationIdSource", source);
        if (eventId != null) {
            messageLog.setStringProperty("eventId", eventId);
        }
        if (eventType != null) {
            messageLog.setStringProperty("eventType", eventType);
        }
        if (eventSource != null) {
            messageLog.setStringProperty("eventSource", eventSource);
        }
        if (eventSubject != null) {
            messageLog.setStringProperty("eventSubject", eventSubject);
        }
    }

    return message;
}
