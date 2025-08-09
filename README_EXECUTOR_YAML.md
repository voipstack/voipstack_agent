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

## Usage in Application

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
