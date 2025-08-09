class Agent::Executor
  abstract class Handler
    abstract def handle_action(action : Agent::Action)
  end

  def initialize
    @handlers = Hash(Agent::ActionMatch, Handler).new
  end

  def when(match : Agent::ActionMatch, handler : Agent::Executor::Handler)
    @handlers[match] = handler
  end

  def execute(action : Agent::Action)
    @handlers.each do |match, handler|
      if action.match?(match)
        handler.handle_action(action)
      end
    end
  end
end
