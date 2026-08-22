# Prowl CLI JSON Schema Bundle

The normative machine-readable Draft 2020-12 bundle is
[`cli-output-schema.json`](../../../ProwlCLIContracts/Resources/cli-output-schema.json).
This document intentionally contains no copied JSON: a Markdown code block cannot
be executed and was the source of the previous schema drift.

## Coverage

The bundle has one versioned success-or-error response schema for every wire command:

| Command | Schema definition |
| --- | --- |
| `open` | `#/$defs/openResponse` |
| `list` | `#/$defs/listResponse` |
| `agents` | `#/$defs/agentsResponse` |
| `agents.read` | `#/$defs/agentsReadResponse` |
| `profiles` | `#/$defs/profilesResponse` |
| `focus` | `#/$defs/focusResponse` |
| `send` | `#/$defs/sendResponse` |
| `key` | `#/$defs/keyResponse` |
| `read` | `#/$defs/readResponse` |
| `create` | `#/$defs/createResponse` |
| `close` | `#/$defs/closeResponse` |
| deprecated `tab` | `#/$defs/tabResponse` |
| deprecated `pane` | `#/$defs/paneResponse` |
| `handoff` | `#/$defs/handoffResponse` |

The bundle root is a `oneOf` across these responses and is valid for any complete
socket response.

## Executable verification

`ProwlCLITests/ProwlCLIIntegrationTests.swift` loads the bundle through the
`ProwlCLIContracts` SwiftPM target and validates every mock socket response that
contains a command payload or error with the Draft 2020-12 `JSONSchema` validator.
Those are raw socket bytes, not decoded model assertions. `make test-cli-integration`
is therefore the contract verification command.

A public wire command is incomplete until its versioned response definition,
socket fixture, parser/handler test, user manual, and command contract change in the
same review.
