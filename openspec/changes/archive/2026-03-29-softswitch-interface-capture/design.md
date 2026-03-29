## Context

The `softswitch-interface` executor type is used to execute commands on softswitches (Asterisk and FreeSWITCH). Currently, it operates in a fire-and-forget manner - it sends commands via AMI (Asterisk) or ESL (FreeSWITCH) but doesn't capture any response data.

This limitation prevents creating stateful workflows where you need to:
1. Start a spy/listen session (creating a new channel)
2. Capture the created channel ID
3. Later stop the session by hanging up that specific channel

The current workaround requires external systems to track channel IDs, which is error-prone and adds complexity.

## Goals / Non-Goals

**Goals:**
- Add a `capture` configuration to `softswitch-interface` actions
- Capture response values from softswitch commands (channel IDs, UUIDs, etc.)
- Store captured values as channel variables on specified channels
- Support both Asterisk (event-based responses) and FreeSWITCH (sync responses)
- Make captured values available for variable substitution in subsequent actions

**Non-Goals:**
- Creating a new executor type (we're extending existing `softswitch-interface`)
- Supporting capture from arbitrary events (only command responses)
- Persistent state storage (only channel variables)
- Bidirectional capture (only output from softswitch to agent)
- Real-time event streaming modifications

## Decisions

### Decision 1: Extend existing type vs. create new type
**Choice:** Extend `softswitch-interface` with optional `capture` field
**Rationale:** The capture is an enhancement to existing functionality, not a fundamentally different executor type. Adding it as optional configuration maintains backward compatibility.
**Alternative considered:** Create new `voipstack` type with built-in capture logic. Rejected because it would duplicate much of the softswitch-interface code.

### Decision 2: Store in channel variables vs. agent memory
**Choice:** Store captured values as softswitch channel variables
**Rationale:** Channel variables persist across agent restarts and are accessible via standard softswitch mechanisms. This also allows external systems to read the values.
**Alternative considered:** Store in agent memory (`@captured_vars`). Rejected because values would be lost on agent restart and wouldn't be visible to external systems.

### Decision 3: Use `target_channel` vs. always using action channel
**Choice:** Allow specifying `target_channel` for variable storage
**Rationale:** The spy/listen use case requires storing the captured spy channel ID on the ORIGINAL channel (the one being spied on), not the newly created spy channel. This gives flexibility.
**Alternative considered:** Always store on the channel from action context. Rejected because it wouldn't support the primary use case.

### Decision 4: Event-based (Asterisk) vs. Sync (FreeSWITCH) handling
**Choice:** Handle differently per softswitch
**Rationale:** Asterisk AMI uses asynchronous events (need to wait for `OriginateResponse`), while FreeSWITCH ESL uses synchronous API calls that return immediately. Each requires different implementation patterns.
**Implementation approach:**
- Asterisk: Wait for `OriginateResponse` event matching `ActionID`, then call `SetVar`
- FreeSWITCH: Parse sync `api()` response, then call `uuid_setvar`

## Risks / Trade-offs

**[Risk]** Capture timeout could leave workflows incomplete
- **Mitigation:** Implement reasonable timeout (30s), log clearly, continue without capture rather than blocking indefinitely

**[Risk]** Channel variable name collisions
- **Mitigation:** Use namespaced variable names (e.g., `VOIPSTACK_CAPTURE_` prefix) in documentation/examples

**[Risk]** Asterisk event correlation complexity
- **Mitigation:** Use unique `ActionID` per originate, store in temporary map while waiting for response

**[Trade-off]** Synchronous capture adds latency
- **Acceptance:** This is necessary for reliable capture. The latency only affects actions with capture enabled.

**[Trade-off]** FreeSWITCH requires different capture source (`api_response` vs `originate_response`)
- **Acceptance:** Document this clearly. Alternative would be abstracting to a generic "response" but that hides important implementation details.

## Migration Plan

No migration needed. This is purely additive - existing YAML configurations without `capture` will continue to work unchanged.

## Open Questions

1. Should we support capturing multiple fields in one action?
   - Current: Single field capture
   - Could extend to array of captures if needed

2. What timeout is appropriate for OriginateResponse wait?
   - Proposed: 30 seconds
   - Could be configurable per-action

3. Should capture failures be fatal or logged-and-continue?
   - Proposed: Log error, continue without capture
   - Alternative: Fail the action
