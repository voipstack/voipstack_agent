## 1. Data Model Updates

- [x] 1.1 Add `match` property to `CaptureConfig` struct in `src/executor.cr`
- [x] 1.2 Update `Agent::ExecutorYaml` to parse optional `match` field from YAML

## 2. Softswitch State Interface Updates

- [x] 2.1 Update `SoftswitchState` abstract methods: `capture_event` and `capture_api_response` to accept optional `match` parameter
- [x] 2.2 Update `AsteriskState.capture_event` implementation to filter events based on match conditions
- [x] 2.3 Update `FreeswitchState.capture_api_response` implementation to filter responses based on match conditions

## 3. Handler Logic Updates

- [x] 3.1 Update `SoftswitchInterfaceHandler.handle_capture` to pass match conditions when present
- [x] 3.2 Add debug logging when capture is skipped due to non-matching conditions

## 4. Testing

- [x] 4.1 Add unit tests for YAML parsing with match conditions
- [x] 4.2 Add tests for Asterisk event filtering with match conditions
- [x] 4.3 Add tests for FreeSWITCH response filtering with match conditions
- [x] 4.4 Add tests verifying AND logic for multiple conditions
- [x] 4.5 Add tests verifying backward compatibility (capture without match still works)

## 5. Documentation

- [x] 5.1 Update `README_EXECUTOR_YAML.md` with match configuration examples
- [x] 5.2 Add example showing OriginateResponse capture with Response: Success condition
