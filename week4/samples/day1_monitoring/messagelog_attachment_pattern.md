# MessageLog attachment pattern — four boundaries on the Order Hub

The Order Hub instrumentation calls `messageLog.addAttachmentAsString(...)` at four named boundaries. Operations can pull any one of them in *Monitor → Message Processing → click run → Attachments* and read the body as it was at that point.

## Why four

A single attachment "request body" tells you the message went in but not where it went wrong. Four well-chosen boundaries let you bisect:

- If `incoming-canonical` is right but `pre-jms` is wrong, the canonicalization or transformation step is the bug.
- If `pre-jms` is right but `post-jms` is wrong, the JMS infrastructure or consumer-side reconstruction is the bug.
- If `post-jms` is right but `pre-receiver` is wrong, the consumer-side enrichment is the bug.

Adding a fifth and sixth is fine if you have a known multi-step transformation. Don't add 20 — the Monitor's Attachments tab becomes a wall.

## The four boundaries

| Boundary name | Where in the canvas | What it captures |
|---|---|---|
| `incoming-canonical` | After the inbound canonicalization step (the iFlow's first business-meaningful step) | The order as the iFlow understood it after parsing — before any enrichment |
| `pre-jms` | Immediately before the JMS Receiver step in the producer iFlow | What was sent onto the queue |
| `post-jms` | Immediately after the JMS Sender (in the consumer iFlow) | What came off the queue — should match `pre-jms` |
| `pre-receiver` | Immediately before the OAuth2 HTTP receiver call to downstream | What was sent to the downstream API |

## Implementation — two options

### Option A: dedicated Groovy script per boundary (verbose, clear)

Inline the `messageLog.addAttachmentAsString(name, content, mimeType)` call in each script.

```groovy
def messageLog = messageLogFactory.createMessageLog(message);
if (messageLog != null) {
    Reader reader = message.getBody(java.io.Reader);
    String body = reader.text;
    messageLog.addAttachmentAsString("pre-jms", body, "application/xml");
    message.setBody(body); // Reader is consumed; restore as String
}
return message;
```

### Option B: shared `roiam_logBoundary.groovy` driven by a Property (DRY)

See `roiam_logBoundary.groovy` in this folder. Upstream of each invocation, set:

- Property `logBoundaryName` = `incoming-canonical` (or whatever boundary)
- Property `logBoundaryMimeType` = `application/xml`

Then call the shared script. Same logic runs everywhere with no copy-paste.

For the Order Hub, **Option B** is recommended — one script in `script/v2/`, four invocations driven by Content Modifier properties.

## Setting `logBoundaryName` via Content Modifier

1. Add Content Modifier immediately before the script invocation.
2. *Exchange Property* tab → Add → Name = `logBoundaryName`, Type = `Constant`, Value = `pre-jms` (or appropriate boundary name).
3. Add a second property `logBoundaryMimeType`, value = `application/xml` (or `application/json` for inbound).

## Mime types

| Stage | Body content | Mime type |
|---|---|---|
| `incoming-canonical` | inbound JSON | `application/json` |
| `pre-jms` | canonical XML for transport | `application/xml` |
| `post-jms` | same canonical XML | `application/xml` |
| `pre-receiver` | downstream API JSON | `application/json` |

If you mis-set the mime type, the Monitor still shows the attachment but renders it as plain text instead of pretty-printing.

## What NOT to attach

- The full HTTP request envelope with `Authorization: Bearer ...` header. Attach just the body.
- Customer PII unless required for triage. If you must, attach to a Subprocess that masks it.
- Multi-megabyte payloads. Attach the first 4 KB plus a note; downstream attachments can capture the rest if needed. (Tenant log store quota.)

## Verification

Send a happy-path call, open the run in Monitor, click Attachments:

- Expect four attachments by name: `incoming-canonical`, `pre-jms`, `post-jms`, `pre-receiver`.
- Expect each to render with correct mime-type formatting.
- Expect each to differ slightly from the previous (post-canonicalization, post-JMS-roundtrip, etc.).

If attachments are missing:

| Missing attachments | Likely cause |
|---|---|
| All four | Log Level set to None or Error; bump to Info |
| Only one or two | The Content Modifier property name is wrong, or the script ran without setting the body back |
| `post-jms` only | The consumer iFlow runs in a separate MPL — check its own attachment list |
