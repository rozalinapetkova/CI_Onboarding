/*
 * Day 2.4 reference solution — v2 refactor of the legacy signer.
 * Place at: scripts/standalone/roiam_bodySigner.groovy
 * Inside the iFlow project: src/main/resources/script/v2/roiam_bodySigner.groovy
 *
 * What changed vs. roiam_legacy_signer_v1_BAD.groovy — see v1_to_v2_diff_walkthrough.md.
 *
 * Deliberate exception to the streaming rule: signing requires the full body bytes,
 * so we materialize it to a String. The StringBuilder loop makes the cost visible.
 */
import com.sap.it.script.v2.api.Message;
import java.io.Reader;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

def Message processData(Message message) {
    def headers = message.getHeaders();

    String secret = headers.get("X-Signing-Secret") as String;
    if (secret == null || secret.isEmpty()) {
        throw new RuntimeException("Missing required header 'X-Signing-Secret'");
    }

    Reader reader = message.getBody(java.io.Reader);
    StringBuilder bodyBuilder = new StringBuilder();
    char[] buffer = new char[4096];
    int read;
    while ((read = reader.read(buffer)) != -1) {
        bodyBuilder.append(buffer, 0, read);
    }
    String body = bodyBuilder.toString();

    String algo = "SHA-256";
    MessageDigest md = MessageDigest.getInstance(algo);
    md.update((body + secret).getBytes(StandardCharsets.UTF_8));
    byte[] digest = md.digest();

    StringBuilder hex = new StringBuilder(digest.length * 2);
    for (byte b : digest) {
        hex.append(String.format("%02x", b));
    }
    String sig = hex.toString();

    def messageLog = messageLogFactory?.createMessageLog(message);
    if (messageLog != null) {
        messageLog.setStringProperty("signatureAlgo", algo);
        // Deliberately NOT logging the secret or the signature itself.
    }

    message.setHeader("X-Body-Signature", sig);
    message.setBody(body);
    return message;
}
