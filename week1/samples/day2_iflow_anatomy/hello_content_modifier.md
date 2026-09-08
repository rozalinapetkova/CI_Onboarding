# Content Modifier — "Set hello body"

## Message Header tab

| Action | Name | Type | Value |
|---|---|---|---|
| Create | `Content-Type` | Constant | `application/json` |

> No other headers. Do not add `correlationId` here — for Hello iFlow we rely on the auto-generated `SAP_MessageProcessingLogID`.

## Message Body tab

- **Type:** *Expression*
- **Body:**

```json
{
  "message": "hello from <your-name>",
  "version": 1
}
```

> Use *Expression* (not *Constant*) only if you want to embed Camel simple expressions later. For a pure literal, Constant also works — pick one and be consistent across the team.

## Exchange Property tab

Leave empty. Hello iFlow has no internal state to carry.
