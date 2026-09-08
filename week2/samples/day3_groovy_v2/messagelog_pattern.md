# `MessageLog` — the only logging that produces output

## The factory is in scope automatically

```groovy
def messageLog = messageLogFactory?.getMessageLog(message);
```

`messageLogFactory` is an SAP-provided binding. **Don't import it.** The `?.` guards against `messageLogFactory` itself being null, which happens in some unit-test harnesses but never at runtime.

## Always null-guard the result

```groovy
if (messageLog != null) {
    messageLog.setStringProperty("orderId", orderId);
    messageLog.addAttachmentAsString("input.json", body, "application/json");
}
```

`getMessageLog(message)` returns `null` when the iFlow's *log level* is **None**. Forgetting the guard is the top cause of "my script throws NPE in prod but worked in test" — because dev tenants default to Trace and prod tenants default to None.

## What each call does

| Call | Effect in MPL |
|---|---|
| `setStringProperty(name, value)` | Adds a key to the run's *Properties* section. **Searchable** via the MPL custom-search box — this is how you find a run by `orderId` weeks later. |
| `addAttachmentAsString(name, content, mime)` | Adds a tab under *Attachments*. Use for diagnostic snapshots: input, output, intermediate state. |
| `setStringProperty(name, value)` with the same name twice | Last write wins. Don't rely on history. |

## Lifetime rules

- **Attachments retention** follows the MPL retention setting (default 30 days for production tenants, 7 for free trials).
- **The attachment write happens immediately** — but if the script throws *after* the attachment write, the attachment is still saved. Conversely, if the script throws *before*, no attachment. Place writes accordingly when debugging.

## What goes in `setStringProperty` vs. an attachment

- **Property** — short, searchable, one-line. `orderId`, `customerId`, `correlationId`, the routing decision, the input format. **Anything you might search for later.**
- **Attachment** — multi-line content. The input body, the output body, the parsed-and-reserialized intermediate, the full stack trace for a partial failure.

## Anti-patterns

- `println` — goes nowhere.
- `System.out.println` — goes nowhere.
- `java.util.logging` — goes nowhere.
- Using `setStringProperty` for multi-line content — truncated and unsearchable.
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
            messageLog.setStringProperty("orderId", orderId);
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

This is the pattern every nontrivial script in the repo follows.
