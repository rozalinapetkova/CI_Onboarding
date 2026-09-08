# `MessageLog` — the only logging that produces output

## The factory is in scope automatically

```groovy
def messageLog = messageLogFactory?.getMessageLog(message);
```

`messageLogFactory` is an SAP-provided binding. **Don't import it.** The `?.` guards against `messageLogFactory` itself being null, which happens in some unit-test harnesses but never at runtime.

## Always null-guard the result

```groovy
if (messageLog != null) {
    messageLog.addCustomHeaderProperty("orderId", orderId);
    messageLog.addAttachmentAsString("input.json", body, "application/json");
}
```

`getMessageLog(message)` returns `null` when the iFlow's *log level* is **None**. Forgetting the guard is the top cause of "my script throws NPE in prod but worked in test" — because dev tenants default to Trace and prod tenants default to None.

## What each call does

| Call | Effect in MPL |
|---|---|
| `addCustomHeaderProperty(name, value)` | Adds a message-wide, **searchable** property. This is how you find a run by `orderId` weeks later, via Monitor's custom-header search. |
| `setStringProperty(name, value)` | Adds a key to *this script step's own* Properties subsection — visible only when you open that step's detail at Debug or Trace level. Not searchable, not message-wide. Use for step-local diagnostics, not for anything operations needs to find a message by. |
| `addAttachmentAsString(name, content, mime)` | Adds a tab under *Attachments*. Use for diagnostic snapshots: input, output, intermediate state. |
| Either call with the same name twice | Last write wins. Don't rely on history. |

## Lifetime rules

- **Attachments retention** follows the MPL retention setting (default 30 days for production tenants, 7 for free trials).
- **The attachment write happens immediately** — but if the script throws *after* the attachment write, the attachment is still saved. Conversely, if the script throws *before*, no attachment. Place writes accordingly when debugging.

## What goes where

- **`addCustomHeaderProperty`** — short, one-line, message-wide, searchable. `orderId`, `customerId`, `correlationId` — anything operations might search for later.
- **`setStringProperty`** — short, one-line, but step-local and not searchable. Diagnostic values useful while actively debugging that one step (e.g. an intermediate routing decision), not business identifiers.
- **Attachment** — multi-line content. The input body, the output body, the parsed-and-reserialized intermediate, the full stack trace for a partial failure.

## Anti-patterns

- `println` — goes nowhere.
- `System.out.println` — goes nowhere.
- `java.util.logging` — goes nowhere.
- Using `setStringProperty` (or `addCustomHeaderProperty`) for multi-line content — gets truncated.
- Expecting `setStringProperty` to be searchable — it never is, regardless of log level. Use `addCustomHeaderProperty` for that.
- Forgetting the null-guard — NPE at runtime when log level is None.
- Calling `getMessageLog(message)` once per branch — fine to call once and reuse the variable.

## Pattern — instrument the whole script

```groovy
def Message processData(Message message) {
    def messageLog = messageLogFactory?.getMessageLog(message);
    Reader reader = message.getBody(java.io.Reader);

    try {
        // ... parse, transform ...
        if (messageLog != null) {
            messageLog.addCustomHeaderProperty("orderId", orderId);
            messageLog.setStringProperty("priority", priority);
            messageLog.addAttachmentAsString("output.xml", out, "application/xml");
        }
        message.setBody(out);
        return message;
    } catch (Exception e) {
        // Even on failure, surface what we had.
        if (messageLog != null) {
            messageLog.setStringProperty("ErrorStep", "jsonOrderToCanonical");
            messageLog.addAttachmentAsString("error.txt",
                e.getMessage() + "\n\n" + e.stackTrace.join("\n"),
                "text/plain");
        }
        message.setProperty("ErrorMessage", e.getMessage());
        message.setProperty("ErrorStep", "jsonOrderToCanonical");
        throw e;
    }
}
```

`orderId` is the business identifier operations searches by, so it's registered as a custom header property. `priority` and `ErrorStep` are step-local diagnostic values, not something anyone searches by, so `setStringProperty` is the right tool for those. This is the pattern every nontrivial script in the repo follows.
