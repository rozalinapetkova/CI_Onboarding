import com.sap.it.script.v2.api.Message;
import com.sap.it.api.pd.PartnerDirectoryService;
import com.sap.it.api.pd.BinaryData;
import com.sap.it.api.ITApiFactory;
import groovy.json.JsonSlurper;
import groovy.json.JsonOutput;
import java.io.Reader;
import java.io.ByteArrayInputStream;

def Message processData(Message message) {
    def headers = message.getHeaders();

    String pid = "ROI_ORDERHUB_ROUTING";
    String parameterId = headers.get("roiam_routing_destination") as String;
    String eventType = headers.get("ce-type") as String;

    if (parameterId == null || parameterId.trim().isEmpty()) {
        throw new RuntimeException("Header 'roiam_routing_destination' is missing or empty");
    }
    if (eventType == null || eventType.trim().isEmpty()) {
        throw new RuntimeException("Header 'ce-type' is missing or empty");
    }

    def pdService = ITApiFactory.getApi(PartnerDirectoryService.class, null);
    if (pdService == null) {
        throw new RuntimeException("Partner Directory service not available");
    }

    BinaryData binary = pdService.getParameter(parameterId, pid, BinaryData);
    if (binary == null) {
        throw new RuntimeException("Routing parameter not found for partnerId: '${pid}', parameterId: '${parameterId}'");
    }

    JsonSlurper jsonSlurper = new JsonSlurper();
    def config = jsonSlurper.parse(new ByteArrayInputStream(binary.getData()));
    if (!(config instanceof Map)) {
        throw new RuntimeException("Partner Directory parameter '${pid}/${parameterId}' is not a JSON object");
    }

    def routes = config.get("routes");
    if (!(routes instanceof Map)) {
        throw new RuntimeException("'routes' missing or not an object in '${pid}/${parameterId}'");
    }

    def matched = routes.get(eventType) ?: routes.get("default");
    if (matched == null) {
        throw new RuntimeException("No route for eventType '${eventType}' and no default in '${pid}/${parameterId}'");
    }

    String targetSystem = matched.get("targetSystem") as String;
    String targetPath = matched.get("targetPath") as String;

    if (targetSystem == null || targetSystem.trim().isEmpty()) {
        throw new RuntimeException("Resolved route missing 'targetSystem' for eventType '${eventType}'");
    }
    if (targetPath == null || targetPath.trim().isEmpty()) {
        throw new RuntimeException("Resolved route missing 'targetPath' for eventType '${eventType}'");
    }

    message.setHeader("roiam_target_system", targetSystem);
    message.setHeader("roiam_target_path", targetPath);

    def messageLog = messageLogFactory.createMessageLog(message);
    if (messageLog != null) {
        messageLog.setStringProperty("targetSystem", targetSystem);
        messageLog.setStringProperty("targetPath", targetPath);
        messageLog.addAttachmentAsString("resolved-route", JsonOutput.toJson(matched), "application/json");
    }

    return message;
}
