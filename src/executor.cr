require "yaml"

class Agent::Executor
  abstract class Handler
    abstract def handle_action(action : Agent::Action) : Array(Agent::Event)
  end

  def initialize
    @handlers = Array(Tuple(Agent::ActionMatch, Handler)).new
  end

  def when(match : Agent::ActionMatch, handler : Agent::Executor::Handler)
    @handlers << {match, handler}
  end

  def execute(action : Agent::Action) : Array(Agent::Event)
    next_events = Array(Agent::Event).new
    @handlers.each do |match, handler|
      if action.match?(match)
        next_events.concat(handler.handle_action(action))
      end
    end
    next_events
  end

  class ProxyHTTPPostHandler < Handler
    def initialize(@handler : Agent::WebHandler)
    end

    def handle_action(action : Agent::Action) : Array(Agent::Event)
      @handler.handle_action(action)
    end
  end

  class ProxySoftswitchStateHandler < Handler
    def initialize(@softswitch : Agent::SoftswitchState)
    end

    def handle_action(action : Agent::Action) : Array(Agent::Event)
      @softswitch.handle_action(action)
    end
  end

  class ShellHandler < Handler
    def initialize(@command : String)
    end

    def handle_action(action : Agent::Action) : Array(Agent::Event)
      env = build_environment(action)
      expanded_command = expand_variables(@command, env)

      stdout = IO::Memory.new
      stderr = IO::Memory.new
      shell = ENV["SHELL"] || "/bin/bash"
      Log.debug { "[EXECUTOR] Using shell: #{shell}" }
      status = Process.run(shell, ["-c", expanded_command],
        output: stdout, error: stderr, env: env)

      events = Array(Agent::Event).new

      if status.success?
        Log.debug { "[EXECUTOR] Shell command executed successfully: #{expanded_command}" }
        Log.debug { "[EXECUTOR] Output: #{stdout.to_s}" }
      else
        Log.error { "[EXECUTOR] Shell command failed: #{expanded_command}" }
        Log.error { "[EXECUTOR] Error: #{stderr.to_s}" }
      end

      events
    end

    private def build_environment(action : Agent::Action) : Hash(String, String)
      env = ENV.to_h

      action.arguments.each do |key, value|
        env["VOIPSTACK_ACTION_INPUT_#{env_input(key).chomp.upcase}"] = env_input(value).chomp
      end

      env["VOIPSTACK_ACTION"] = action.action
      env["VOIPSTACK_ACTION_ID"] = action.id
      env["VOIPSTACK_APP_ID"] = action.app_id
      env["VOIPSTACK_HANDLER"] = action.@handler

      env
    end

    private def env_input(input : String) : String
      input.gsub(/[^a-zA-Z0-9_\-]/, "")
    end

    private def expand_variables(command : String, env : Hash(String, String)) : String
      result = command
      env.each do |key, value|
        result = result.gsub("${#{key}}", value)
      end
      result
    end
  end
end

module Agent::ExecutorYaml
  struct ActionConfig
    include YAML::Serializable

    property type : String
    property when : Hash(String, String | Hash(String, String))
    property command : String?
  end

  struct ExecutorConfig
    include YAML::Serializable

    property executor : Hash(String, ActionConfig)
  end

  def self.from_yaml(yaml_content : String) : Agent::Executor
    config = ExecutorConfig.from_yaml(yaml_content)
    executor = Agent::Executor.new

    config.executor.each do |name, action_config|
      Log.debug { "[EXECUTOR] Creating handler for action #{name}" }
      handler = case action_config.type
                when "shell"
                  command = action_config.command
                  raise "Shell action requires command" unless command
                  Agent::Executor::ShellHandler.new(command)
                else
                  raise "Unknown action type: #{action_config.type}"
                end

      executor.when(action_config.when, handler)
    end

    executor
  end

  def self.from_file(yaml_path : String) : Agent::Executor
    yaml_content = File.read(yaml_path)
    from_yaml(yaml_content)
  end
end
