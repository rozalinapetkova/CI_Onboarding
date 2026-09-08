/*
 * Day 2.3 — demonstrating the sandbox restrictions.
 * NOT meant to be deployed; this is annotated wrong-vs-right reference code.
 */
import com.sap.it.script.v2.api.Message;

def Message processData(Message message) {

    // ----- 1. Sleeping -----

    // WRONG — java.lang.Thread is blocked by the sandbox. Deploy succeeds,
    //         the step throws at runtime.
    // Thread.sleep(1000);

    // RIGHT — Groovy's sleep is a method on DefaultGroovyMethods, not Thread.
    sleep(1000) { /* runs only if interrupted */ };


    // ----- 2. File I/O -----

    // WRONG — file system access is sandboxed away.
    // new File("/tmp/x.txt").text = "hello";

    // RIGHT — there is no right. The runtime has no file system you can use.
    //         Persist via Data Store or Number Range instead. See Day 3.4.


    // ----- 3. HTTP from a script -----

    // WRONG — direct socket-level access is forbidden.
    // new URL("https://example.com").openConnection();

    // RIGHT (rarely) — SAP's HttpClient bypasses the sandbox check:
    //   import com.sap.it.api.asdk.runtime.HttpClientFactory;
    //   def httpClient = new HttpClientFactory().newHttpClient();
    //
    // RIGHTER — use a Request-Reply step with an HTTP receiver adapter.
    //           Only fall back to HttpClient when the iFlow flow cannot express
    //           the call (e.g., fan-out inside a transformation).


    // ----- 4. Logging -----

    // WRONG — output goes nowhere.
    // System.out.println("hello");
    // println "hello";

    // RIGHT — MessageLog. The factory is in scope automatically (no import).
    def messageLog = messageLogFactory?.createMessageLog(message);
    if (messageLog != null) {
        messageLog.addAttachmentAsString("diag.txt", "hello", "text/plain");
    }


    // ----- 5. Process/system exits -----

    // WRONG — both are blocked.
    // System.exit(0);
    // Runtime.getRuntime().exec("ls");


    // ----- 6. Top-level classes -----

    // Cannot demonstrate inline; the violation is putting `class Foo {}` at
    // the top of the file alongside processData. Compiles in IDE, fails to
    // deploy. Use methods (like helperBelow() below) or closures instead.

    return message;
}

Object helperBelow() {
    // Method declared at top level is fine — it's not a class.
    return null;
}
