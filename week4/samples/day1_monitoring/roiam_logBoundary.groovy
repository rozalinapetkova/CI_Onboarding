import com.sap.it.script.v2.api.Message;
import java.io.Reader;

// Day 4.1 — drop-in MessageLog boundary attachment.
//
// Reads the current body (without consuming the stream irreversibly for
// downstream steps), attaches it to the MPL under a boundary name read from a
// property, and continues. Use this at four points in the Order Hub:
//   - after inbound canonicalization → property logBoundaryName = "incoming-canonical"
//   - before JMS send                → property logBoundaryName = "pre-jms"
//   - after JMS receive (consumer)   → property logBoundaryName = "post-jms"
//   - before receiver call            → property logBoundaryName = "pre-receiver"
//
// Set `logBoundaryName` and `logBoundaryMimeType` via Content Modifier
// (Exchange Property) immediately upstream of each invocation.
//
// Null-guard on messageLog is mandatory — Log Level may be None at runtime.

def Message processData(Message message) {
    def properties = message.getProperties();

    String boundaryName = properties.get("logBoundaryName") as String;
    String mimeType = (properties.get("logBoundaryMimeType") as String) ?: "application/xml";

    if (boundaryName == null || boundaryName.trim().isEmpty()) {
        // Misconfigured — don't crash the run, but record the slip-up.
        boundaryName = "boundary-unnamed";
    }

    Reader reader = message.getBody(java.io.Reader);
    StringBuilder bodyBuilder = new StringBuilder();
    char[] buf = new char[4096];
    int n;
    while ((n = reader.read(buf)) != -1) {
        bodyBuilder.append(buf, 0, n);
    }
    String bodyString = bodyBuilder.toString();

    def messageLog = messageLogFactory.getMessageLog(message);
    if (messageLog != null) {
        messageLog.addAttachmentAsString(boundaryName, bodyString, mimeType);
    }

    // Restore body for downstream steps — Reader is now consumed.
    message.setBody(bodyString);
    return message;
}
