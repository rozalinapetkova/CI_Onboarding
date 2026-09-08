import com.sap.it.script.v2.api.Message;

// Classify a consumer-iFlow exception as Retry (transient) or Bypass (permanent).
// Place on the FIRST step inside the Exception Subprocess.
// Reads:  property CamelExceptionCaught, header CamelHttpResponseCode
// Writes: property errorCategory, header X-Error-Category, MessageLog stringProperty errorCategory
//
// Downstream Router branches on ${property.errorCategory}:
//   Retry  -> rethrow (let JMS retry-and-eventually-DLQ).
//   Bypass -> send to DLQ via JMS receiver adapter, then End (swallow exception).

def Message processData(Message message) {
    def headers = message.getHeaders();
    def properties = message.getProperties();

    Object exHeader = properties.get("CamelExceptionCaught");
    String exClass = exHeader != null ? exHeader.getClass().getName() : "";
    String exMsg = exHeader != null ? (exHeader.getMessage() ?: "") : "";

    Integer httpCode = null;
    Object rawCode = headers.get("CamelHttpResponseCode");
    if (rawCode != null) {
        try {
            httpCode = rawCode as Integer;
        } catch (Exception ignore) {
            httpCode = null;
        }
    }

    String category = "Retry";
    String reason = "default: unclassified -> retry";

    // Permanent HTTP client errors -> Bypass.
    // Exceptions: 408 Request Timeout and 429 Too Many Requests are transient.
    if (httpCode != null && httpCode >= 400 && httpCode < 500
            && httpCode != 408 && httpCode != 429) {
        category = "Bypass";
        reason = "HTTP " + httpCode + " is a permanent client error";
    }

    // Schema / payload validation failures are permanent.
    if (exClass.contains("ValidationException")
            || exClass.contains("SchemaValidationException")
            || exClass.contains("XmlSchemaValidationException")) {
        category = "Bypass";
        reason = "validation failure (" + exClass + ")";
    }

    // 5xx and connection-level exceptions stay as Retry (the default), explicitly noted.
    if (httpCode != null && httpCode >= 500) {
        reason = "HTTP " + httpCode + " is a transient server error";
    }
    if (exClass.contains("ConnectException")
            || exClass.contains("SocketTimeoutException")
            || exClass.contains("UnknownHostException")) {
        reason = "network-level exception (" + exClass + ")";
    }

    message.setProperty("errorCategory", category);
    message.setProperty("errorReason", reason);
    message.setHeader("X-Error-Category", category);

    def messageLog = messageLogFactory.getMessageLog(message);
    if (messageLog != null) {
        messageLog.setStringProperty("errorCategory", category);
        messageLog.setStringProperty("errorReason", reason);
        messageLog.setStringProperty("httpResponseCode", httpCode != null ? httpCode.toString() : "n/a");
        messageLog.setStringProperty("exceptionClass", exClass);
        messageLog.addAttachmentAsString(
            "categorization",
            "category=" + category + "\nreason=" + reason + "\nhttpCode=" + httpCode + "\nexClass=" + exClass + "\nexMsg=" + exMsg,
            "text/plain"
        );
    }

    return message;
}
