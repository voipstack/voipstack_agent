## 1. Update YAML Configuration

- [x] 1.1 Add `capture` property to `ActionConfig` struct in `src/executor_yaml.cr`
- [x] 1.2 Define `CaptureConfig` struct with `from`, `extract`, `store`, and `target_channel` fields
- [x] 1.3 Update YAML deserialization to handle optional capture blocks

## 2. Implement Capture in SoftswitchInterfaceHandler

- [x] 2.1 Modify `SoftswitchInterfaceHandler` to check for capture configuration
- [x] 2.2 Add `capture_response` method that delegates to softswitch-specific implementation
- [x] 2.3 Integrate capture flow: execute command → wait for response → extract → set variable
- [x] 2.4 Add error handling and timeout logic
- [x] 3.1 Add `capture_originate_response` method to `AsteriskState`
- [x] 3.2 Implement ActionID generation and tracking for Originate commands
- [x] 3.3 Create event correlation mechanism to match OriginateResponse with ActionID
- [x] 3.4 Add timeout handling (30 second default)
- [x] 3.5 Add `set_channel_var` method using AMI SetVar action

## 4. FreeSWITCH State Implementation

- [x] 4.1 Add `capture_api_response` method to `FreeswitchState`
- [x] 4.2 Implement parsing of sync API response (e.g., "+OK <uuid>")
- [x] 4.3 Add `set_channel_var` method using ESL uuid_setvar API
- [x] 5.1 Wire capture logic into executor flow
- [x] 5.2 Ensure captured values are available for variable substitution
- [x] 5.3 Add unit tests for capture configuration parsing
- [x] 5.4 Add integration tests for Asterisk capture flow
- [x] 5.5 Add integration tests for FreeSWITCH capture flow

## 6. Documentation

- [x] 6.1 Update `README_EXECUTOR_YAML.md` with capture configuration syntax
- [x] 6.2 Add examples for Asterisk Originate with capture
- [x] 6.3 Add examples for FreeSWITCH originate with capture
- [x] 6.4 Document capture timeout behavior and error handling
