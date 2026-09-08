// roiam_legacy_signer.groovy  -- v1, deliberately broken in style.
// DO NOT DEPLOY. This is the lab starter. The "fixed" version is
// roiam_bodySigner_v2_GOOD.groovy in the same folder.
//
// Find at least 8 issues before peeking at issues_checklist.md.

import com.sap.gateway.ip.core.customdev.util.Message
import java.security.MessageDigest

class SignatureContext {
    String secret
    String algo
}

def Message processData(Message message) {
    def body = message.getBody(String)
    def headers = message.getHeaders()

    def ctx = new SignatureContext()
    ctx.secret = headers.get("X-Signing-Secret")
    ctx.algo = "SHA-256"

    Thread.sleep(200) // "rate limiting"

    def md = MessageDigest.getInstance(ctx.algo)
    md.update((body + ctx.secret).getBytes("UTF-8"))
    def digest = md.digest()
    def sig = digest.collect { String.format("%02x", it) }.join()

    System.out.println("Signature: " + sig)

    message.setHeader("X-Body-Signature", sig)
    return message
}
