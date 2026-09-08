import com.sap.it.script.v2.api.Message;
import java.util.UUID;

// Day 4.1 — first step after the sender adapter on every iFlow.
//
// Accepts an inbound `correlationId` header if the caller supplies one (e.g., a
// chained iFlow propagating its own trace); generates a fresh UUID otherwise.
// Sets the header on the message and registers it as an MPL searchable property
// so operations can filter by it in Monitor.
//
// Place under script/v2/ inside the iFlow project; upload via the Script step
// dialog (not the Resources tab) per the project rule.

def Message processData(Message message) {
    def headers = message.getHeaders();

    String correlationId = headers.get("correlationId") as String;
    if (correlationId == null || correlationId.trim().isEmpty()) {
        correlationId = UUID.randomUUID().toString();
    }
    message.setHeader("correlationId", correlationId);

    def messageLog = messageLogFactory.getMessageLog(message);
    if (messageLog != null) {
        messageLog.addCustomHeaderProperty("correlationId", correlationId);
    }

    return message;
}
