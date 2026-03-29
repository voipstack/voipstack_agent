## ADDED Requirements

### Requirement: Capture softswitch event responses
The system SHALL support capturing values from any softswitch event responses and storing them as channel variables for use in subsequent actions.

#### Scenario: Capture any event field on Asterisk
- **WHEN** an action with type `softswitch-interface` is executed with `capture.from: event:<EventName>`
- **AND** the softswitch is Asterisk
- **THEN** the system SHALL wait for the specified event with matching `ActionID`
- **AND** extract the value from the specified field (e.g., `Channel`, `Uniqueid`)
- **AND** execute `SetVar` on the `target_channel` to store the captured value

#### Scenario: Capture OriginateResponse Channel on Asterisk
- **WHEN** an action has `capture: { from: "event:OriginateResponse", extract: "Channel" }`
- **THEN** the system SHALL capture the `Channel` field from the `OriginateResponse` event

#### Scenario: Capture Newchannel Uniqueid on Asterisk
- **WHEN** an action has `capture: { from: "event:Newchannel", extract: "Uniqueid" }`
- **THEN** the system SHALL capture the `Uniqueid` field from the `Newchannel` event

#### Scenario: Capture API response UUID on FreeSWITCH
- **WHEN** an action with type `softswitch-interface` is executed with `capture.from: api_response`
- **AND** the softswitch is FreeSWITCH
- **THEN** the system SHALL parse the synchronous API response (e.g., "+OK <uuid>")
- **AND** extract the UUID from the response
- **AND** execute `uuid_setvar` on the `target_channel` to store the captured value

### Requirement: Use captured values in subsequent actions
The system SHALL make captured values available as variables in subsequent action configurations.

#### Scenario: Reference captured channel in hangup action
- **WHEN** a previous action captured a value and stored it as `VOIPSTACK_SPY` on a channel
- **AND** a subsequent action uses `${VOIPSTACK_SPY}` in its interface configuration
- **THEN** the system SHALL substitute `${VOIPSTACK_SPY}` with the actual captured value
- **AND** execute the command with the substituted value

### Requirement: Capture configuration validation
The system SHALL validate capture configuration and fail gracefully on misconfiguration.

#### Scenario: Invalid capture target channel
- **WHEN** an action has `capture.target_channel` that cannot be resolved
- **THEN** the system SHALL log an error
- **AND** skip the capture but continue with the command execution

#### Scenario: Missing capture source
- **WHEN** an action has `capture` block but no `from` field
- **THEN** the system SHALL raise a configuration error
- **AND** prevent the action from executing

### Requirement: Capture timeout handling
The system SHALL handle timeouts when waiting for asynchronous responses.

#### Scenario: Event timeout on Asterisk
- **WHEN** waiting for an event on Asterisk
- **AND** no response is received within a reasonable timeout (e.g., 30 seconds)
- **THEN** the system SHALL log a timeout error
- **AND** return without setting the channel variable
