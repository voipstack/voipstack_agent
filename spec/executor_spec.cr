require "./spec_helper"

class TestHandler < Agent::Executor::Handler
  getter :called

  def initialize
    @called = ""
  end

  def handle_action(action : Agent::Action) : Array(Agent::Event)
    @called = action.action
    Array(Agent::Event).new
  end
end

describe Agent::Executor do
  it "execute action when match condition" do
    test_handler = TestHandler.new
    executor = Agent::Executor.new
    action = Agent::Action.new(
      id: "123",
      app_id: "test",
      action: "test",
      handler: "dial",
      arguments: Agent::ActionArgument.new,
      handler_arguments: Agent::ActionArgument.new
    )
    match = Agent::ActionMatch.new
    match["handler"] = "dial"
    match["action"] = "test"
    executor.when(match, test_handler)
    executor.execute(action)
    test_handler.called.should eq "test"
  end

  it "executes action when match condition with arguments" do
    test_handler = TestHandler.new
    executor = Agent::Executor.new
    arguments = Agent::ActionArgument.new
    arguments["key"] = "value"
    action = Agent::Action.new(
      id: "789",
      app_id: "test",
      action: "test_with_args",
      handler: "process",
      arguments: arguments,
      handler_arguments: Agent::ActionArgument.new
    )
    match = Agent::ActionMatch.new
    match["handler"] = "process"
    match["action"] = "test_with_args"
    match["arguments"] = {"key" => "value"}
    executor.when(match, test_handler)
    executor.execute(action)
    test_handler.called.should eq "test_with_args"
  end

  it "executes action considering handler_arguments" do
    test_handler = TestHandler.new
    executor = Agent::Executor.new
    handler_arguments = Agent::ActionArgument.new
    handler_arguments["handler_key"] = "handler_value"
    action = Agent::Action.new(
      id: "101",
      app_id: "test_app",
      action: "handler_test",
      handler: "handler_process",
      arguments: Agent::ActionArgument.new,
      handler_arguments: handler_arguments
    )
    match = Agent::ActionMatch.new
    match["handler"] = "handler_process"
    match["action"] = "handler_test"
    match["handler_arguments"] = {"handler_key" => "handler_value"}
    executor.when(match, test_handler)
    executor.execute(action)
    test_handler.called.should eq "handler_test"
  end

  it "does not execute action when handler_arguments do not match" do
    test_handler = TestHandler.new
    executor = Agent::Executor.new
    handler_arguments = Agent::ActionArgument.new
    handler_arguments["handler_key"] = "other_value"
    action = Agent::Action.new(
      id: "112",
      app_id: "test_app",
      action: "handler_test",
      handler: "handler_process",
      arguments: Agent::ActionArgument.new,
      handler_arguments: handler_arguments
    )
    match = Agent::ActionMatch.new
    match["handler"] = "handler_process"
    match["action"] = "handler_test"
    match["handler_arguments"] = {"handler_key" => "handler_value"}
    executor.when(match, test_handler)
    executor.execute(action)
    test_handler.called.should eq ""
  end

  it "does not execute action when no match condition" do
    test_handler = TestHandler.new
    executor = Agent::Executor.new
    action = Agent::Action.new(
      id: "456",
      app_id: "test_app",
      action: "test_action",
      handler: "message",
      arguments: Agent::ActionArgument.new,
      handler_arguments: Agent::ActionArgument.new
    )
    match = Agent::ActionMatch.new
    match["handler"] = "dial"
    match["action"] = "test"
    executor.when(match, test_handler)
    executor.execute(action)
    test_handler.called.should eq ""
  end

  it "does not execute action when skip" do
    test_handler = TestHandler.new
    executor = Agent::Executor.new
    action = Agent::Action.new(
      id: "123",
      app_id: "test",
      action: "test",
      handler: "dial",
      arguments: Agent::ActionArgument.new,
      handler_arguments: Agent::ActionArgument.new
    )
    match = Agent::ActionMatch.new
    match["handler"] = "dial"
    match["action"] = "test"
    opts = Agent::Executor::Options.new.skip(true)
    executor.when(match, test_handler, opts)

    executor.execute(action)

    test_handler.called.should eq ""
  end
end
