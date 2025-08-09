class Agent::Executor
  abstract class Handler
    abstract def handle_action(action : Agent::Action) : Agent::Events
  end

  def initialize
    @handlers = Hash(Agent::ActionMatch, Handler).new
  end

  def when(match : Agent::ActionMatch, handler : Agent::Executor::Handler)
    @handlers[match] = handler
  end

  def execute(action : Agent::Action) : Agent::Events
    next_events = Agent::Events.new
    @handlers.each do |match, handler|
      if action.match?(match)
        next_events.concat(handler.handle_action(action))
      end
    end
    next_events
  end
end
