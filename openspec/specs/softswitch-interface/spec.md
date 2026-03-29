## Requirements

### Requirement: Execute softswitch commands via AMI/ESL
The system SHALL execute softswitch commands and forward events.

#### Scenario: Execute Originate on Asterisk
- **WHEN** an action with type `softswitch-interface` is executed
- **AND** the command is `Originate`
- **THEN** the system SHALL send the command via Asterisk AMI
- **AND** return any resulting events

#### Scenario: Execute API command on FreeSWITCH
- **WHEN** an action with type `softswitch-interface` is executed
- **AND** the command is an API command
- **THEN** the system SHALL send the command via FreeSWITCH ESL
- **AND** return the response

#### Scenario: Execute with capture configuration
- **WHEN** an action has `capture` configuration defined
- **THEN** the system SHALL wait for the appropriate response (event or sync)
- **AND** extract the specified field value
- **AND** store it as a channel variable on the target channel
