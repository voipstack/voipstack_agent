## Why

The current capture functionality captures the first event or response it receives. In practice, events like `OriginateResponse` can have different outcomes (Success, Failure, etc.). Users need to conditionally capture values only when specific field conditions are met, such as only capturing the Channel when the Response is "Success".

## What Changes

- Add optional `match` field to capture configuration that filters events/responses before extraction
- Support matching on event/response fields using AND logic (all conditions must match)
- Works with both Asterisk (event-based) and FreeSWITCH (sync response) capture patterns
- If no match is found within timeout, capture is skipped without error

**Example YAML:**
```yaml
capture:
  from: event:OriginateResponse
  extract: Channel
  store: VOIPSTACK_SPY_CHANNEL
  target_channel: ${VOIPSTACK_ACTION_VENDOR_CHANNEL}
  wait_timeout_ms: 500
  match:
    interface:
      Response: Success
```

## Capabilities

### New Capabilities
- (none)

### Modified Capabilities
- `executor-capture`: Add conditional filtering with `match` field to capture only when specified event/response field conditions are met

## Impact

- `CaptureConfig` struct in `src/executor.cr` - add `match` property
- `SoftswitchState` abstract methods - `capture_event` and `capture_api_response` need match parameter
- `AsteriskState` implementation - filter events based on match conditions
- `FreeswitchState` implementation - filter API responses based on match conditions
- `Agent::ExecutorYaml` - parse optional `match` field from YAML
