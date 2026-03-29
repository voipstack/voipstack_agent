# ExecutorYaml - YAML-Configured Action Execution

The ExecutorYaml module provides a declarative way to configure action handlers using YAML files, enabling shell command execution with environment variable substitution.

## Quick Start

```crystal
require "./src/agent"

# Load from YAML string
yaml_content = <<-YAML
executor:
  test_action:
    type: shell
    when:
      action: test
      handler: dial
    command: "echo ${VOIPSTACK_ACTION_INPUT_MESSAGE}"
YAML

executor = Agent::ExecutorYaml.from_yaml(yaml_content)

# Or load from file
executor = Agent::ExecutorYaml.from_file("config/executor.yml")
```

## YAML Configuration Format

```yaml
executor:
  <action_name>:
    type: <handler_type>
    when:
      <match_conditions>
    command: <shell_command>
    skip: <bool>          # Optional: skip this handler
    break: <bool>         # Optional: stop execution after this handler
    only_for: <string>    # Optional: only execute for specific softswitch
```

### Handler Types

#### Shell Handler

Executes shell commands with environment variable expansion:

```yaml
executor:
  call_handler:
    type: shell
    when:
      action: call
      handler: dial
    command: "echo 'Calling ${VOIPSTACK_ACTION_INPUT_NUMBER}'"
```

### Match Conditions

Define when actions should execute:

```yaml
# Simple string matching
when:
  action: test
  handler: dial

# Nested argument matching
when:
  action: process
  handler: data
  arguments:
    type: important
```

### Execution Control Options

#### skip

Skip execution of this handler:

```yaml
executor:
  disabled_action:
    type: shell
    skip: true
    when:
      action: test
    command: "echo 'This will not execute'"
```

#### break

Stop execution chain after this handler executes. Useful when you want to prevent subsequent handlers from processing the same action:

```yaml
executor:
  audio_stream:
    type: softswitch-interface
    break: true
    when:
      action: start
      app_id: audio
    command: Originate
    interface:
      Channel: PJSIP/6002/sip:voipstack@${VOIPSTACK_GLOBAL_AGENT_MEDIA_SIP_HOST}:${VOIPSTACK_GLOBAL_AGENT_MEDIA_SIP_PORT}
```

#### only_for

Execute only for a specific softswitch type:

```yaml
executor:
  freeswitch_audio:
    type: softswitch-interface
    only_for: "freeswitch"
    when:
      action: start
      app_id: audio
    command: api
    interface:
      originate: "{sip_h_X-VOIPSTACK-STREAM-IN-URL=${VOIPSTACK_ACTION_INPUT_INPUT_STREAM_IN_URL}}sofia/internal/voipstack@..."
```

### Environment Variables

Available in shell commands:

- `VOIPSTACK_ACTION` - Action name
- `VOIPSTACK_ACTION_ID` - Action ID
- `VOIPSTACK_APP_ID` - Application ID
- `VOIPSTACK_HANDLER` - Handler name
- `VOIPSTACK_ACTION_INPUT_<KEY>` - Action arguments (uppercased)

## Examples

### Basic Echo Command

```yaml
executor:
  echo_test:
    type: shell
    when:
      action: test
      handler: dial
    command: "echo 'Test: ${VOIPSTACK_ACTION_INPUT_MESSAGE}'"
```

### Multiple Actions

```yaml
executor:
  start_call:
    type: shell
    when:
      action: call
      handler: dial
    command: "asterisk -rx 'channel originate SIP/${VOIPSTACK_ACTION_INPUT_NUMBER}'"
  
  end_call:
    type: shell
    when:
      action: hangup
      handler: call_control
    command: "asterisk -rx 'channel request hangup ${VOIPSTACK_ACTION_INPUT_CHANNEL}'"
```

### Webhook Integration

```yaml
executor:
  webhook_notify:
    type: shell
    when:
      action: notify
      handler: webhook
    command: |
      curl -X POST "${VOIPSTACK_ACTION_INPUT_WEBHOOK_URL}" \
        -H "Content-Type: application/json" \
        -d "{\"message\": \"${VOIPSTACK_ACTION_INPUT_MESSAGE}\"}"
```

### Softswitch Interface Handler

Execute softswitch interface commands (AMI for Asterisk, ESL for FreeSWITCH):

```yaml
executor:
  hangup_asterisk:
    type: softswitch-interface
    when:
      action: hangup
    command: Hangup
    interface:
      Channel: ${VOIPSTACK_ACTION_VENDOR_CHANNEL}

  asterisk_audio:
    type: softswitch-interface
    only_for: "asterisk"
    break: true
    when:
      action: start
      app_id: audio
    command: Originate
    interface:
      Channel: PJSIP/6002/sip:voipstack@${VOIPSTACK_GLOBAL_AGENT_MEDIA_SIP_HOST}:${VOIPSTACK_GLOBAL_AGENT_MEDIA_SIP_PORT}
      Application: ChanSpy
      Data: ${VOIPSTACK_ACTION_VENDOR_CHANNEL},q
      Variable: "PJSIP_HEADER(add,X-VOIPSTACK-STREAM-IN-URL)=${VOIPSTACK_ACTION_INPUT_INPUT_STREAM_IN_URL}"
      Async: true
```

### Capture Configuration

Capture responses from softswitch commands and store them as channel variables for use in subsequent actions:

```yaml
executor:
  listen_start:
    type: softswitch-interface
    only_for: "asterisk"
    break: true
    when:
      action: start
      app_id: audio
    execute: Originate
    interface:
      Channel: PJSIP/6002/sip:voipstack@${VOIPSTACK_GLOBAL_AGENT_MEDIA_SIP_HOST}:${VOIPSTACK_GLOBAL_AGENT_MEDIA_SIP_PORT}
      Application: ChanSpy
      Data: ${VOIPSTACK_ACTION_VENDOR_CHANNEL},q
    capture:
      from: originate_response
      extract: Channel
      store: VOIPSTACK_SPY
      target_channel: ${VOIPSTACK_ACTION_VENDOR_CHANNEL}

  listen_stop:
    type: softswitch-interface
    only_for: "asterisk"
    when:
      action: stop
      app_id: audio
    execute: Hangup
    interface:
      Channel: ${VOIPSTACK_SPY}
```

**Capture Fields:**

- `from`: Source of the response
  - `event:<EventName>` - For Asterisk events (e.g., `event:OriginateResponse`, `event:Newchannel`)
  - `api_response` - For FreeSWITCH synchronous API responses
- `extract`: Field to extract from the response (e.g., `Channel`, `Uniqueid`, `uuid`)
- `store`: Variable name to store the captured value
- `target_channel`: Channel on which to set the variable (supports variable substitution)

**Capture from Newchannel event (Asterisk):**

```yaml
executor:
  track_new_channel:
    type: softswitch-interface
    only_for: "asterisk"
    when:
      action: create
    execute: Originate
    interface:
      Channel: PJSIP/6002/...
    capture:
      from: event:Newchannel
      extract: Uniqueid
      store: VOIPSTACK_CREATED_CHANNEL_UID
      target_channel: ${VOIPSTACK_ACTION_VENDOR_CHANNEL}
```

**FreeSWITCH Example:**

```yaml
executor:
  listen_start:
    type: softswitch-interface
    only_for: "freeswitch"
    when:
      action: start
      app_id: audio
    execute: api
    interface:
      originate: "{process_cdr=false,sip_h_X-VOIPSTACK-STREAM-IN-URL=${VOIPSTACK_ACTION_INPUT_INPUT_STREAM_IN_URL}}sofia/internal/voipstack@${VOIPSTACK_GLOBAL_AGENT_MEDIA_SIP_HOST}:${VOIPSTACK_GLOBAL_AGENT_MEDIA_SIP_PORT} &eavesdrop(${VOIPSTACK_ACTION_INPUT_CALL_UUID})"
    capture:
      from: api_response
      extract: uuid
      store: VOIPSTACK_SPY
      target_channel: ${VOIPSTACK_ACTION_INPUT_CALL_UUID}
```

**Timeout Behavior:**

- Capture operations have a 30-second timeout
- If timeout occurs, the variable is not set but the command continues
- Errors are logged for debugging

### Capture with Match Conditions

You can conditionally capture only when specific field conditions are met. This is useful for capturing only successful responses:

```yaml
executor:
  listen_start:
    type: softswitch-interface
    only_for: "asterisk"
    break: true
    when:
      action: start
      app_id: audio
    execute: Originate
    interface:
      Channel: PJSIP/6002/sip:voipstack@${VOIPSTACK_GLOBAL_AGENT_MEDIA_SIP_HOST}:${VOIPSTACK_GLOBAL_AGENT_MEDIA_SIP_PORT}
      Application: ChanSpy
      Data: ${VOIPSTACK_ACTION_VENDOR_CHANNEL},q
    capture:
      from: event:OriginateResponse
      extract: Channel
      store: VOIPSTACK_SPY
      target_channel: ${VOIPSTACK_ACTION_VENDOR_CHANNEL}
      match:
        interface:
          Response: Success
```

**Match Fields:**

- `match.interface`: Contains key-value pairs to match against event/response fields
- All conditions must match (AND logic) for capture to proceed
- If conditions don't match, capture is skipped silently
- If no `match` is specified, all events/responses are captured (backward compatible)

**Multiple Match Conditions:**

```yaml
capture:
  from: event:OriginateResponse
  extract: Channel
  store: VOIPSTACK_SPY
  target_channel: ${VOIPSTACK_ACTION_VENDOR_CHANNEL}
  match:
    interface:
      Response: Success
      Reason: "4"
```

**FreeSWITCH API Response Matching:**

For FreeSWITCH, match against `status` field:

```yaml
executor:
  originate_call:
    type: softswitch-interface
    only_for: "freeswitch"
    when:
      action: start
    execute: api
    interface:
      originate: "{process_cdr=false}sofia/internal/voipstack@... &park()"
    capture:
      from: api_response
      extract: uuid
      store: VOIPSTACK_CALL_UUID
      target_channel: ${VOIPSTACK_ACTION_VENDOR_CHANNEL}
      match:
        interface:
          status: success
```

```crystal
# Create executor
executor = Agent::ExecutorYaml.from_file("config/actions.yml")

# Create action
arguments = Agent::ActionArgument.new
arguments["message"] = "Hello World"

action = Agent::Action.new(
  id: UUID.random.to_s,
  app_id: "my_app",
  action: "test",
  handler: "dial",
  arguments: arguments,
  handler_arguments: Agent::ActionArgument.new
)

# Execute
events = executor.execute(action)
```

## Testing

Run ExecutorYaml tests:

```bash
crystal spec spec/executor_yaml_spec.cr
```

Run all tests:

```bash
crystal spec
```

## Error Handling

The module handles:

- Unknown action types
- Missing required fields
- Invalid YAML syntax
- Shell command failures

```crystal
begin
  executor = Agent::ExecutorYaml.from_yaml(invalid_yaml)
rescue ex
  puts "Configuration error: #{ex.message}"
end
```

## Integration with CLI

Add to existing CLI application:

```crystal
# In cli.cr
executor_config_path = ENV["VOIPSTACK_EXECUTOR_CONFIG"]?
if executor_config_path && File.exists?(executor_config_path)
  yaml_executor = Agent::ExecutorYaml.from_file(executor_config_path)
  
  actions.execute do |action|
    events = yaml_executor.execute(action)
    events.each { |event| collector.push(event) }
  end
end
```

## Best Practices

1. **Security**: Validate input parameters before shell execution
2. **Logging**: Monitor command execution and failures
3. **Testing**: Test YAML configurations with various input scenarios
4. **Performance**: Consider command execution time for real-time applications

## File Structure

```
agent/
├── src/
│   ├── executor.cr              # Core executor + ExecutorYaml
│   └── agent.cr                 # Main agent module
├── spec/
│   ├── executor_spec.cr         # Original executor tests
│   └── executor_yaml_spec.cr    # ExecutorYaml tests
├── examples/
│   ├── executor_config.yml      # Sample configuration
│   ├── executor_yaml_example.cr # Usage example
│   └── cli_integration.cr       # CLI integration example
└── docs/
    └── executor_yaml.md         # Detailed documentation
```
