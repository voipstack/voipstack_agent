require "./spec_helper"

# Mock softswitch state for testing
describe "Capture and Retrieve" do
  it "handles capture configuration" do
    yaml_content = <<-YAML
    executor:
      capture_action:
        type: softswitch-interface
        when:
          action: start
          app_id: audio
        command: Originate
        interface:
          Channel: PJSIP/6002/...
          Application: ChanSpy
          Data: "PJSIP/channel,q"
        capture:
          from: event:OriginateResponse
          extract: Channel
          store: VOIPSTACK_SPY
          target_channel: PJSIP/original-channel
    YAML

    # Create a mock softswitch
    mock_softswitch = TestSoftswitchState.new("test-id")
    
    executor = Agent::ExecutorYaml.from_yaml(yaml_content) do |action_config|
      if action_config.type == "softswitch-interface"
        Agent::Executor::SoftswitchInterfaceHandler.new(
          softswitch: mock_softswitch,
          command: action_config.command.not_nil!,
          interface: action_config.interface.not_nil!.clone,
          capture: action_config.capture
        )
      else
        raise "Unknown action type"
      end
    end

    # Execute the action
    action = Agent::Action.new(
      id: "123",
      app_id: "test",
      action: "start",
      handler: "audio",
      arguments: Agent::ActionArgument.new,
      handler_arguments: Agent::ActionArgument.new,
      vendor: {"channel" => "PJSIP/original-channel"}
    )

    events = executor.execute(action)
    events.should be_a(Array(Agent::Event))
  end

  it "handles retrieve configuration" do
    yaml_content = <<-YAML
    executor:
      retrieve_action:
        type: softswitch-interface
        when:
          action: stop
          app_id: audio
        command: Hangup
        interface:
          Channel: "${VOIPSTACK_SPY}"
        retrieve:
          source_channel: PJSIP/original-channel
          extract: VOIPSTACK_SPY
          store: VOIPSTACK_SPY
    YAML

    # Create a mock softswitch with pre-set variable
    mock_softswitch = TestSoftswitchState.new("test-id")
    mock_softswitch.set_test_var("PJSIP/original-channel", "VOIPSTACK_SPY", "PJSIP/spy-channel")
    
    executor = Agent::ExecutorYaml.from_yaml(yaml_content) do |action_config|
      if action_config.type == "softswitch-interface"
        Agent::Executor::SoftswitchInterfaceHandler.new(
          softswitch: mock_softswitch,
          command: action_config.command.not_nil!,
          interface: action_config.interface.not_nil!.clone,
          retrieve: action_config.retrieve
        )
      else
        raise "Unknown action type"
      end
    end

    action = Agent::Action.new(
      id: "456",
      app_id: "test",
      action: "stop",
      handler: "audio",
      arguments: Agent::ActionArgument.new,
      handler_arguments: Agent::ActionArgument.new,
      vendor: {"channel" => "PJSIP/original-channel"}
    )

    events = executor.execute(action)
    events.should be_a(Array(Agent::Event))
    
    # Verify the interface was updated with retrieved value
    # Note: In real implementation, we'd check the interface was modified
  end

  it "handles both capture and retrieve in sequence" do
    yaml_content = <<-YAML
    executor:
      capture_action:
        type: softswitch-interface
        when:
          action: start
        command: Originate
        interface:
          Channel: PJSIP/6002/...
        capture:
          from: event:OriginateResponse
          extract: Channel
          store: VOIPSTACK_SPY
          target_channel: PJSIP/original
      retrieve_action:
        type: softswitch-interface
        when:
          action: stop
        command: Hangup
        interface:
          Channel: "${VOIPSTACK_SPY}"
        retrieve:
          source_channel: PJSIP/original
          extract: VOIPSTACK_SPY
          store: VOIPSTACK_SPY
    YAML

    mock_softswitch = TestSoftswitchState.new("test-id")
    
    executor = Agent::ExecutorYaml.from_yaml(yaml_content) do |action_config|
      if action_config.type == "softswitch-interface"
        Agent::Executor::SoftswitchInterfaceHandler.new(
          softswitch: mock_softswitch,
          command: action_config.command.not_nil!,
          interface: action_config.interface.not_nil!.clone,
          capture: action_config.capture,
          retrieve: action_config.retrieve
        )
      else
        raise "Unknown action type"
      end
    end

    # First action - capture
    capture_action = Agent::Action.new(
      id: "789",
      app_id: "test",
      action: "start",
      handler: "audio",
      arguments: Agent::ActionArgument.new,
      handler_arguments: Agent::ActionArgument.new,
      vendor: {"channel" => "PJSIP/original"}
    )

    events1 = executor.execute(capture_action)
    events1.should be_a(Array(Agent::Event))

    # Simulate setting the captured value
    mock_softswitch.set_test_var("PJSIP/original", "VOIPSTACK_SPY", "PJSIP/spy-123")

    # Second action - retrieve
    retrieve_action = Agent::Action.new(
      id: "790",
      app_id: "test",
      action: "stop",
      handler: "audio",
      arguments: Agent::ActionArgument.new,
      handler_arguments: Agent::ActionArgument.new,
      vendor: {"channel" => "PJSIP/original"}
    )

    events2 = executor.execute(retrieve_action)
    events2.should be_a(Array(Agent::Event))
  end

  it "handles capture with match conditions" do
    yaml_content = <<-YAML
    executor:
      capture_action:
        type: softswitch-interface
        when:
          action: start
          app_id: audio
        command: Originate
        interface:
          Channel: PJSIP/6002/...
        capture:
          from: event:OriginateResponse
          extract: Channel
          store: VOIPSTACK_SPY
          target_channel: PJSIP/original-channel
          match:
            interface:
              Response: Success
    YAML

    # Create a mock softswitch
    mock_softswitch = TestSoftswitchState.new("test-id")

    executor = Agent::ExecutorYaml.from_yaml(yaml_content) do |action_config|
      if action_config.type == "softswitch-interface"
        Agent::Executor::SoftswitchInterfaceHandler.new(
          softswitch: mock_softswitch,
          command: action_config.command.not_nil!,
          interface: action_config.interface.not_nil!.clone,
          capture: action_config.capture
        )
      else
        raise "Unknown action type"
      end
    end

    # Execute the action - must match YAML conditions
    action = Agent::Action.new(
      id: "123",
      app_id: "audio",
      action: "start",
      handler: "audio",
      arguments: Agent::ActionArgument.new,
      handler_arguments: Agent::ActionArgument.new,
      vendor: {"channel" => "PJSIP/original-channel"}
    )

    events = executor.execute(action)
    events.should be_a(Array(Agent::Event))

    # Verify match conditions were passed
    mock_softswitch.last_match_conditions.should_not be_nil
    match = mock_softswitch.last_match_conditions.not_nil!
    match["Response"].should eq("Success")
  end

  it "handles capture with multiple match conditions" do
    yaml_content = <<-YAML
    executor:
      capture_action:
        type: softswitch-interface
        when:
          action: start
          app_id: audio
        command: Originate
        interface:
          Channel: PJSIP/6002/...
        capture:
          from: event:OriginateResponse
          extract: Channel
          store: VOIPSTACK_SPY
          target_channel: PJSIP/original
          match:
            interface:
              Response: Success
              Reason: "4"
    YAML

    mock_softswitch = TestSoftswitchState.new("test-id")

    executor = Agent::ExecutorYaml.from_yaml(yaml_content) do |action_config|
      if action_config.type == "softswitch-interface"
        Agent::Executor::SoftswitchInterfaceHandler.new(
          softswitch: mock_softswitch,
          command: action_config.command.not_nil!,
          interface: action_config.interface.not_nil!.clone,
          capture: action_config.capture
        )
      else
        raise "Unknown action type"
      end
    end

    action = Agent::Action.new(
      id: "123",
      app_id: "audio",
      action: "start",
      handler: "audio",
      arguments: Agent::ActionArgument.new,
      handler_arguments: Agent::ActionArgument.new,
      vendor: {"channel" => "PJSIP/original"}
    )

    events = executor.execute(action)
    events.should be_a(Array(Agent::Event))

    # Verify multiple match conditions were passed
    match = mock_softswitch.last_match_conditions.not_nil!
    match["Response"].should eq("Success")
    match["Reason"].should eq("4")
  end

  it "handles capture without match conditions (backward compatibility)" do
    yaml_content = <<-YAML
    executor:
      capture_action:
        type: softswitch-interface
        when:
          action: start
          app_id: audio
        command: Originate
        interface:
          Channel: PJSIP/6002/...
        capture:
          from: event:OriginateResponse
          extract: Channel
          store: VOIPSTACK_SPY
          target_channel: PJSIP/original
    YAML

    mock_softswitch = TestSoftswitchState.new("test-id")

    executor = Agent::ExecutorYaml.from_yaml(yaml_content) do |action_config|
      if action_config.type == "softswitch-interface"
        Agent::Executor::SoftswitchInterfaceHandler.new(
          softswitch: mock_softswitch,
          command: action_config.command.not_nil!,
          interface: action_config.interface.not_nil!.clone,
          capture: action_config.capture
        )
      else
        raise "Unknown action type"
      end
    end

    action = Agent::Action.new(
      id: "123",
      app_id: "audio",
      action: "start",
      handler: "audio",
      arguments: Agent::ActionArgument.new,
      handler_arguments: Agent::ActionArgument.new,
      vendor: {"channel" => "PJSIP/original"}
    )

    events = executor.execute(action)
    events.should be_a(Array(Agent::Event))

    # Verify no match conditions were passed (nil)
    mock_softswitch.last_match_conditions.should be_nil
  end
end

# Test helper class for mocking softswitch state
class TestSoftswitchState < Agent::SoftswitchState
  @test_vars = {} of String => Hash(String, String)
  @last_match_conditions : Hash(String, String)? = nil
  @last_timeout_ms : Int32 = 30000

  def initialize(@softswitch_id : String)
  end

  def software : String
    "test"
  end

  def version : String
    "1.0"
  end

  def setup(config, driver_config_path = nil)
  end

  def bootstrap : Array(Agent::Event)
    [] of Agent::Event
  end

  def interface_command(command : String, input : Hash(String, String)) : Array(Agent::Event)
    Log.debug { "[TEST] interface_command: #{command} with #{input}" }
    [] of Agent::Event
  end

  def handle_action(action : Agent::Action) : Array(Agent::Event)
    [] of Agent::Event
  end

  def next_platform_events : Array(Agent::Event)
    [] of Agent::Event
  end

  def capture_event(event_name : String, command : String, input : Hash(String, String), extract_field : String, timeout_ms : Int32 = 30000, match : Hash(String, String)? = nil) : String?
    @last_match_conditions = match
    @last_timeout_ms = timeout_ms
    # Simulate capturing a value
    "PJSIP/captured-#{UUID.random}"
  end

  def capture_api_response(command : String, input : Hash(String, String), match : Hash(String, String)? = nil) : String?
    @last_match_conditions = match
    # Simulate capturing from API response
    "test-uuid-123"
  end

  def set_channel_var(channel : String, variable : String, value : String)
    @test_vars[channel] ||= {} of String => String
    @test_vars[channel][variable] = value
    Log.debug { "[TEST] Set #{variable}=#{value} on #{channel}" }
  end

  def get_channel_var(channel : String, variable : String) : String?
    @test_vars[channel]?.try(&.[variable]?)
  end

  def set_test_var(channel : String, variable : String, value : String)
    @test_vars[channel] ||= {} of String => String
    @test_vars[channel][variable] = value
  end

  def last_match_conditions : Hash(String, String)?
    @last_match_conditions
  end

  def last_timeout_ms : Int32
    @last_timeout_ms
  end
end