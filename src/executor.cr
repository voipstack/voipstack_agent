require "yaml"

class Agent::Executor
  class Options
    def initialize
      @skip = false
    end

    def skip(value)
      @skip = value
      self
    end

    def skip?
      @skip
    end
  end

  abstract class Handler
    abstract def handle_action(action : Agent::Action) : Array(Agent::Event)
  end

  def initialize
    @handlers = Array(Tuple(Agent::ActionMatch, Handler, Options)).new
  end

  def when(match : Agent::ActionMatch, handler : Agent::Executor::Handler, opts : Agent::Executor::Options = Agent::Executor::Options.new)
    @handlers << {match, handler, opts}
  end

  def execute(action : Agent::Action) : Array(Agent::Event)
    next_events = Array(Agent::Event).new
    @handlers.each do |match, handler, opts|
      if action.match?(match) && !opts.skip?
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

  class SoftswitchInterfaceHandler < Handler
    def initialize(@softswitch : Agent::SoftswitchState, @command : String, @interface : Hash(String, String), @globals = Hash(String, String).new)
    end

    def handle_action(action : Agent::Action) : Array(Agent::Event)
      interpolated_interface = @interface.clone
      action.arguments.each do |key, value|
        expand_variables("VOIPSTACK_ACTION_INPUT_", key, value, interpolated_interface)
      end

      action.vendor.each do |key, value|
        expand_variables("VOIPSTACK_ACTION_VENDOR_", key, value, interpolated_interface)
      end

      @globals.each do |key, value|
        expand_variables("VOIPSTACK_GLOBAL_", key, value, interpolated_interface)
      end

      Log.debug { "[EXECUTOR] SOFTSWITCH INTERFACE COMMAND: #{interpolated_interface.inspect}" }

      @softswitch.interface_command(@command, interpolated_interface)
    end

    private def expand_variables(prefix, key, value, variables : Hash(String, String))
      variables.keys.each do |interface_key|
        key = "#{prefix}#{key.chomp.upcase}"
        if variables[interface_key].includes? "${#{key}}"
          variables[interface_key] = variables[interface_key].gsub("${#{key}}", value)
        end
      end
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
    property interface : Hash(String, String)?
    property skip : Bool? = false
  end

  struct ExecutorConfig
    include YAML::Serializable

    property executor : Hash(String, ActionConfig)
  end

  def self.from_yaml(yaml_content : String, &) : Agent::Executor
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
                  yield action_config
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
