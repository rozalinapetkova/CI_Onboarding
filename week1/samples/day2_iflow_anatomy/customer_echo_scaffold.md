# Customer Echo Service — Day 1.2 scaffold

> On Day 1.2 you only build the **shell**. Day 1.3 wires the HTTPS receiver call to restcountries; Day 1.4 splits in a ProcessDirect consumer. Don't put any of that in yet.

## iFlow id

`roi_<initials>_CustomerEchoService`

## Sender adapter (HTTPS)

| Setting | Value |
|---|---|
| Address | `/customer/<initials>/echo` |
| CSRF Protected | `false` (Day 1.5 will turn this on for the production-style variant) |
| Authorization | Role-based |
| User Role | `ESBMessaging.send` |
| Message Exchange Pattern | Request-Reply (default) |

## Allowed methods

POST only. The validator in `Day 1.3` will reject anything else.

## Placeholder body (Content Modifier "Echo back")

```json
{
  "echo": "stub — Day 1.3 fills in country lookup",
  "received": "${in.body}"
}
```

This is intentionally ugly — the `${in.body}` substitution is a Camel simple expression that embeds the raw inbound body. It proves the round-trip works before we add transformation logic.

## What this scaffold does NOT have yet

- No JSON schema validation (Day 1.3 adds it)
- No country lookup (Day 1.3)
- No ProcessDirect handoff to a logger (Day 1.4)
- No Data Store write (Day 1.4)
- No error subprocess (Week 4)

Keep the scaffold *boring*. The whole point of a week-long progression is to add one concept at a time and watch the message flow change.
