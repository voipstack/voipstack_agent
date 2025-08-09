require "./spec_helper"

class StubGetter < Agent::ActionGetter
  @actions = Agent::Actions.new

  def add(action : Agent::Action)
    @actions << action
  end

  def fetch : Agent::Actions
    @actions
  end
end

describe Agent::ActionRunner do
  crypto = Agent::DumbOpenSSL.new

  it "run heartbeat action" do
    getter = StubGetter.new
    getter.add(Agent::Action.new(id: "123", app_id: "appid", action: "heartbeat", arguments: Agent::ActionArgument.new, handler: "dial", handler_arguments: Agent::ActionArgument.new))
    runner = Agent::ActionRunner.new(getter: getter)

    resp = Channel(Agent::Action).new
    spawn do
      runner.execute do |action|
        resp.send action
      end
    end

    select
    when action = resp.receive
      action.action.should eq "heartbeat"
    when timeout(1.second)
      raise "timeout"
    end
  end

  it "run next action" do
    getter = StubGetter.new
    getter.add(Agent::Action.new(id: "123", app_id: "appid", action: "heartbeat", arguments: Agent::ActionArgument.new, handler: "dial", handler_arguments: Agent::ActionArgument.new))
    runner = Agent::ActionRunner.new(getter: getter)

    resp = Channel(Agent::Action).new
    spawn do
      runner.execute do |action|
        resp.send action
      end
    end

    select
    when action = resp.receive
      action.action.should eq "heartbeat"
    when timeout(1.second)
      raise "timeout"
    end

    getter.add(Agent::Action.new(id: "1234", app_id: "appid", action: "hupall", arguments: Agent::ActionArgument.new, handler: "dial", handler_arguments: Agent::ActionArgument.new))
    getter.add(Agent::Action.new(id: "12345", app_id: "appid", action: "shutdown", arguments: Agent::ActionArgument.new, handler: "dial", handler_arguments: Agent::ActionArgument.new))
    resp = Channel(Agent::Action).new
    spawn do
      runner.execute do |action|
        resp.send action
      end
    end

    select
    when action = resp.receive
      action.action.should eq "hupall"
    when timeout(1.second)
      raise "timeout"
    end
    select
    when action = resp.receive
      action.action.should eq "shutdown"
    when timeout(1.second)
      raise "timeout"
    end
  end

  it "POST to server" do
    http_mock = http_expect_once %({"data":{"actions":[{"app_id":"appid","id":"123","previous_id":null,"action":"heartbeat","handler":"dial","handler_arguments":{},"arguments":{},"vendor":{}}]}})
    http_client = Agent::HTTPClient.new(crypto)
    getter = Agent::ActionHTTPGetter.new("http://localhost:8080", "123", http_client: http_client)
    runner = Agent::ActionRunner.new(getter: getter)

    resp = Channel(Agent::Action).new
    spawn do
      runner.execute do |action|
        resp.send action
      end
    end

    select
    when action = resp.receive
      action.action.should eq "heartbeat"
    when timeout(1.second)
      raise "timeout"
    end
  end
end
