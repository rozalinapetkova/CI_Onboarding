# Restricted classes — what the CI sandbox blocks

The sandbox blocks classes that could:
- Escape the JVM (file system, sockets, process control)
- Hold resources across executions (threads)
- Destabilize the tenant (System.exit, Runtime.exec)

| Class / API | Why blocked | Replacement |
|---|---|---|
| `java.lang.Thread` | Thread management is owned by Camel | `sleep(ms){ onInterrupt }` (Groovy's `sleep`, not Thread's) — or split into multiple iFlow steps |
| `Thread.sleep(ms)` | Same | `sleep(500) { interrupted -> /* handle */ };` |
| `Thread.currentThread()` | Same | Don't reach for thread context — store state in message properties |
| `System.exit(...)` | Would kill the Camel worker | Throw a `RuntimeException` |
| `Runtime.getRuntime().exec(...)` | Process spawn blocked | No replacement — this is not a CI use case |
| `System.out.println` / `System.err.println` | Output discarded | `MessageLog.addAttachmentAsString` / `setStringProperty` |
| `java.util.logging.*` | Output discarded | Same |
| `println` (Groovy default) | Output discarded | Same |
| `java.io.File`, `java.nio.file.Files`, `Paths.get` | No file system in sandbox | Data Store (Day 3.4) or properties |
| `new FileInputStream(...)` / `FileWriter` | Same | Same |
| `java.net.Socket` / `ServerSocket` | No outbound from script | HTTP receiver adapter in the iFlow flow |
| `new URL(...).openConnection()` | Same | Same — or `HttpClientFactory` (sparingly) |
| `@Grab` / `groovy.grape.Grape` | No internet at compile time, no Maven resolver | Use only runtime classpath classes |
| Top-level `class Foo {}` alongside `processData` | Script engine refuses to load such files | Inline helper as a closure or method inside the script body; or put it in a Script Collection |
| Top-level `enum` / `record` / `interface` | Same | Same |

## The two surprises every cohort hits

### 1. `Thread.sleep` looks fine — it isn't

```groovy
// WRONG — deploys, throws at runtime
Thread.sleep(1000);

// RIGHT
sleep(1000) { /* runs only if interrupted */ };
```

Groovy's `sleep` is a method on `DefaultGroovyMethods`, not `Thread`. It takes a closure as second argument (the interrupt handler). The closure is optional in pure Groovy but **project convention is to write it** even if empty — to make the choice visible.

### 2. Top-level classes look fine — they aren't

```groovy
// WRONG — file refuses to deploy
import com.sap.it.script.v2.api.Message;

class OrderItem {
    String sku;
    int qty;
}

def Message processData(Message message) { ... }
```

The CI script engine compiles the file as a Groovy *script* (executable body), not as a Groovy *class*. Classes at the top level violate the script grammar.

Two ways out:
- **Use a `Map`** with the same fields: `[sku: 'A-100', qty: 10]`.
- **Move the class to a Script Collection** — a separate resource artifact that *is* compiled as a class file, and added to the iFlow as a referenced collection. Overkill for two fields.

In the body of `processData` you *can* declare local classes (rare and not encouraged) or use closures:

```groovy
def Message processData(Message message) {
    def buildItem = { sku, qty -> [sku: sku, qty: qty] };
    def items = [buildItem('A-100', 10), buildItem('A-205', 5)];
    // ...
}
```

## Quick test: will it deploy?

If your script contains any of these tokens at column 1 of any line *outside* `processData`'s braces, it won't deploy:
- `class `
- `enum `
- `record `
- `interface `
- `trait `

Helper *methods* (with `def` or a return type at column 1) are fine — they're top-level definitions, not classes.
