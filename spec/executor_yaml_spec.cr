require "./spec_helper"

describe Agent::ExecutorYaml do
  it "parses YAML configuration and creates executor" do
    yaml_content = <<-YAML
    executor:
      action:
        type: shell
        when:
          action: test
          handler: dial
        command: "echo test_output"
    YAML

    executor = Agent::ExecutorYaml.from_yaml(yaml_content) do |action_config|
      raise "Invalid action configuration"
    end

    action = Agent::Action.new(
      id: "123",
      app_id: "test",
      action: "test",
      handler: "dial",
      arguments: Agent::ActionArgument.new,
      handler_arguments: Agent::ActionArgument.new
    )

    events = executor.execute(action)
    events.should be_a(Array(Agent::Event))
  end

  it "expands environment variables in shell commands" do
    yaml_content = <<-YAML
    executor:
      action:
        type: shell
        when:
          action: test
          handler: dial
        command: "echo ${VOIPSTACK_ACTION_INPUT_INPUT}"
    YAML

    executor = Agent::ExecutorYaml.from_yaml(yaml_content) do |action_config|
      raise "Invalid action configuration"
    end

    arguments = Agent::ActionArgument.new
    arguments["input"] = "hello_world"

    action = Agent::Action.new(
      id: "456",
      app_id: "test",
      action: "test",
      handler: "dial",
      arguments: arguments,
      handler_arguments: Agent::ActionArgument.new
    )

    events = executor.execute(action)
    events.should be_a(Array(Agent::Event))
  end

  it "handles multiple actions with different conditions" do
    yaml_content = <<-YAML
    executor:
      test_action:
        type: shell
        when:
          action: test
          handler: dial
        command: "echo test"
      another_action:
        type: shell
        when:
          action: another
          handler: process
        command: "echo another"
    YAML

    executor = Agent::ExecutorYaml.from_yaml(yaml_content) do |action_config|
      raise "Invalid action configuration"
    end

    test_action = Agent::Action.new(
      id: "1",
      app_id: "test",
      action: "test",
      handler: "dial",
      arguments: Agent::ActionArgument.new,
      handler_arguments: Agent::ActionArgument.new
    )

    another_action = Agent::Action.new(
      id: "2",
      app_id: "test",
      action: "another",
      handler: "process",
      arguments: Agent::ActionArgument.new,
      handler_arguments: Agent::ActionArgument.new
    )

    executor.execute(test_action).should be_a(Array(Agent::Event))
    executor.execute(another_action).should be_a(Array(Agent::Event))
  end

  it "raises error for unknown action type" do
    yaml_content = <<-YAML
    executor:
      action:
        type: unknown
        when:
          action: test
          handler: dial
        command: "echo test"
    YAML

    expect_raises(Exception, "Unknown action type: unknown") do
      executor = Agent::ExecutorYaml.from_yaml(yaml_content) do |action_config|
        raise "Unknown action type: #{action_config.type}"
      end
    end
  end

  it "raises error for shell action without command" do
    yaml_content = <<-YAML
    executor:
      action:
        type: shell
        when:
          action: test
          handler: dial
    YAML

    expect_raises(Exception, "Shell action requires command") do
      executor = Agent::ExecutorYaml.from_yaml(yaml_content) do |action_config|
        raise "Invalid action configuration"
      end
    end
  end

  it "does not execute action when conditions don't match" do
    yaml_content = <<-YAML
    executor:
      action:
        type: shell
        when:
          action: test
          handler: dial
        command: "echo test"
    YAML

    executor = Agent::ExecutorYaml.from_yaml(yaml_content) do |action_config|
      raise "Invalid action configuration"
    end

    action = Agent::Action.new(
      id: "123",
      app_id: "test",
      action: "different",
      handler: "dial",
      arguments: Agent::ActionArgument.new,
      handler_arguments: Agent::ActionArgument.new
    )

    events = executor.execute(action)
    events.size.should eq 0
  end

  it "does not execute action when skip" do
    yaml_content = <<-YAML
    executor:
      action:
        type: shell
        skip: true
        when:
          action: test
          handler: dial
        command: "echo test"
    YAML

    executor = Agent::ExecutorYaml.from_yaml(yaml_content) do |action_config|
      raise "Invalid action configuration"
    end

    action = Agent::Action.new(
      id: "123",
      app_id: "test",
      action: "test",
      handler: "dial",
      arguments: Agent::ActionArgument.new,
      handler_arguments: Agent::ActionArgument.new
    )

    events = executor.execute(action)
    events.size.should eq 0
  end
end
