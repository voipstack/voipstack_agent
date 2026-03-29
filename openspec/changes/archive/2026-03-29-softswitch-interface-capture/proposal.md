## Why

The `softswitch-interface` executor type currently operates in a fire-and-forget manner. When executing softswitch commands like `Originate` (Asterisk) or `originate` (FreeSWITCH), there's no way to capture the response (e.g., the created channel ID) and use it in subsequent actions. This limits the ability to create stateful workflows, such as starting a spy/listen session and later stopping it by referencing the created channel. By adding a `capture` capability, we can extract values from softswitch responses and store them as channel variables for later retrieval.

## What Changes

- Extend `softswitch-interface` executor type with optional `capture` field
- Add `capture` configuration with the following properties:
  - `from`: Event/response source (`originate_response` for Asterisk, `api_response` for FreeSWITCH)
  - `extract`: Field to extract from the response (e.g., `Channel`, `uuid`)
  - `store`: Variable name to store the captured value
  - `target_channel`: Channel on which to set the variable (uses SetVar on Asterisk, uuid_setvar on FreeSWITCH)
- Update `SoftswitchInterfaceHandler` to:
  - Wait for and parse OriginateResponse events (Asterisk) or synchronous API responses (FreeSWITCH)
  - Extract specified fields from responses
  - Call appropriate softswitch methods to set channel variables
- Support for both Asterisk AMI (event-based) and FreeSWITCH ESL (sync response) patterns

## Capabilities

### New Capabilities
- `executor-capture`: Capture softswitch command responses and store values as channel variables for use in subsequent actions

### Modified Capabilities
- `softswitch-interface`: Add optional `capture` field to action configuration that enables response capture and channel variable storage

## Impact

- **Executor YAML parsing**: `ActionConfig` struct in `src/executor_yaml.cr` needs new `capture` property
- **Softswitch handlers**: `SoftswitchInterfaceHandler` in `src/executor.cr` needs capture logic
- **AsteriskState**: New methods to wait for `OriginateResponse` events and set channel variables via `SetVar`
- **FreeswitchState**: New methods to parse sync API responses and set channel variables via `uuid_setvar`
- **Documentation**: Update `README_EXECUTOR_YAML.md` with capture configuration examples
