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

  it "stops execution when break option is set in YAML" do
    yaml_content = <<-YAML
    executor:
      first_action:
        type: shell
        break: true
        when:
          action: test
          handler: dial
        command: "echo first"
      second_action:
        type: shell
        when:
          action: test
          handler: dial
        command: "echo second"
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

  it "continues execution when break is false in YAML" do
    yaml_content = <<-YAML
    executor:
      first_action:
        type: shell
        break: false
        when:
          action: test
          handler: dial
        command: "echo first"
      second_action:
        type: shell
        when:
          action: test
          handler: dial
        command: "echo second"
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

  it "parses capture configuration in YAML" do
    yaml_content = <<-YAML
    executor:
      capture_action:
        type: softswitch-interface
        when:
          action: start
          app_id: audio
        execute: Originate
        interface:
          Channel: PJSIP/6002/...
          Application: ChanSpy
          Data: "PJSIP/channel,q"
        capture:
          from: originate_response
          extract: Channel
          store: VOIPSTACK_SPY
          target_channel: "${VOIPSTACK_ACTION_VENDOR_CHANNEL}"
    YAML

    executor = Agent::ExecutorYaml.from_yaml(yaml_content) do |action_config|
      # Verify capture config was parsed correctly
      action_config.capture.should_not be_nil
      capture = action_config.capture.not_nil!
      capture.from.should eq("originate_response")
      capture.extract.should eq("Channel")
      capture.store.should eq("VOIPSTACK_SPY")
      capture.target_channel.should eq("${VOIPSTACK_ACTION_VENDOR_CHANNEL}")
      Agent::Executor::ShellHandler.new("echo test")
    end
  end

  it "allows actions without capture configuration" do
    yaml_content = <<-YAML
    executor:
      no_capture_action:
        type: shell
        when:
          action: test
          handler: dial
        command: "echo test"
    YAML

    executor = Agent::ExecutorYaml.from_yaml(yaml_content) do |action_config|
      action_config.capture.should be_nil
      Agent::Executor::ShellHandler.new("echo test")
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

  it "parses retrieve configuration in YAML" do
    yaml_content = <<-YAML
    executor:
      retrieve_action:
        type: softswitch-interface
        when:
          action: stop
          app_id: audio
        execute: Hangup
        interface:
          Channel: "${CHANNEL}"
        retrieve:
          source_channel: "${VOIPSTACK_ACTION_VENDOR_CHANNEL}"
          extract: VOIPSTACK_SPY
          store: SPY_CHANNEL
    YAML

    executor = Agent::ExecutorYaml.from_yaml(yaml_content) do |action_config|
      # Verify retrieve config was parsed correctly
      action_config.retrieve.should_not be_nil
      retrieve = action_config.retrieve.not_nil!
      retrieve.source_channel.should eq("${VOIPSTACK_ACTION_VENDOR_CHANNEL}")
      retrieve.extract.should eq("VOIPSTACK_SPY")
      retrieve.store.should eq("SPY_CHANNEL")
      Agent::Executor::ShellHandler.new("echo test")
    end
  end

  it "combines skip and break options correctly in YAML" do
    yaml_content = <<-YAML
    executor:
      first_action:
        type: shell
        skip: true
        break: true
        when:
          action: test
          handler: dial
        command: "echo first"
      second_action:
        type: shell
        when:
          action: test
          handler: dial
        command: "echo second"
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
