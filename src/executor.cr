require "yaml"

class Agent::Executor
  class Options
    def initialize
      @skip = false
      @break = false
    end

    def skip(value)
      @skip = value
      self
    end

    def skip?
      @skip
    end

    def break(value)
      @break = value
      self
    end

    def break?
      @break
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
        break if opts.break?
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
    def initialize(@softswitch : Agent::SoftswitchState, @command : String, @interface : Hash(String, String), @globals = Hash(String, String).new, @only_for : String? = nil, @capture : CaptureConfig? = nil, @retrieve : RetrieveConfig? = nil)
    end

    def handle_action(action : Agent::Action) : Array(Agent::Event)
      if @only_for && @softswitch.software != @only_for
        Log.debug { "[EXECUTOR] SOFTSWITCH INTERFACE HANDLER: only_for=#{@only_for} but software=#{@softswitch.software}, skipping" }
        return [] of Agent::Event
      end

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

      # Handle retrieve if configured - read from channel vars into interface
      if retrieve = @retrieve
        handle_retrieve(retrieve, interpolated_interface, action)
      end

      Log.debug { "[EXECUTOR] SOFTSWITCH INTERFACE COMMAND: #{interpolated_interface.inspect}" }

      # Execute command
      events = @softswitch.interface_command(@command, interpolated_interface)

      # Handle capture if configured
      if capture = @capture
        handle_capture(capture, interpolated_interface, action)
      end

      events
    end

    private def handle_retrieve(retrieve : RetrieveConfig, interface : Hash(String, String), action : Agent::Action)
      # Get source channel with variable substitution
      source_channel = retrieve.source_channel
      action.arguments.each do |key, value|
        source_channel = source_channel.gsub("${VOIPSTACK_ACTION_INPUT_#{key.upcase}}", value)
      end
      action.vendor.each do |key, value|
        source_channel = source_channel.gsub("${VOIPSTACK_ACTION_VENDOR_#{key.upcase}}", value)
      end

      begin
        # Read channel variable
        if value = @softswitch.get_channel_var(source_channel, retrieve.extract)
          # Store in interface using the 'store' name as the key
          interface[retrieve.store] = value
          Log.debug { "[EXECUTOR] Retrieved '#{retrieve.extract}' from '#{source_channel}' -> '#{retrieve.store}' = '#{value}'" }
        else
          Log.error { "[EXECUTOR] Failed to retrieve '#{retrieve.extract}' from '#{source_channel}'" }
        end
      rescue ex
        Log.error { "[EXECUTOR] Retrieve failed: #{ex.message}" }
      end
    end

    private def handle_capture(capture : CaptureConfig, interface : Hash(String, String), action : Agent::Action)
      # Get target channel with variable substitution
      target_channel = capture.target_channel
      action.arguments.each do |key, value|
        target_channel = target_channel.gsub("${VOIPSTACK_ACTION_INPUT_#{key.upcase}}", value)
      end
      action.vendor.each do |key, value|
        target_channel = target_channel.gsub("${VOIPSTACK_ACTION_VENDOR_#{key.upcase}}", value)
      end

      begin
        # Capture response based on softswitch type
        captured_value = nil
        if capture.from.starts_with?("event:")
          event_name = capture.from.sub("event:", "")
          captured_value = @softswitch.capture_event(event_name, @command, interface, capture.extract)
        elsif capture.from == "api_response"
          captured_value = @softswitch.capture_api_response(@command, interface)
        else
          Log.error { "[EXECUTOR] Unknown capture source: #{capture.from}" }
          return
        end

        if captured_value
          # Set channel variable
          @softswitch.set_channel_var(target_channel, capture.store, captured_value)
          Log.debug { "[EXECUTOR] Captured value '#{captured_value}' stored as '#{capture.store}' on channel '#{target_channel}'" }
        else
          Log.error { "[EXECUTOR] Failed to capture value from #{capture.from}" }
        end
      rescue ex
        Log.error { "[EXECUTOR] Capture failed: #{ex.message}" }
      end
    end

    private def expand_variables(prefix, key, value, variables : Hash(String, String))
      variables.keys.each do |interface_key|
        full_key = "#{prefix}#{key.chomp.upcase}"
        if variables[interface_key].includes? "${#{full_key}}"
          variables[interface_key] = variables[interface_key].gsub("${#{full_key}}", value)
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

module Agent
  struct CaptureConfig
    include YAML::Serializable

    property from : String
    property extract : String
    property store : String
    property target_channel : String
  end

  struct RetrieveConfig
    include YAML::Serializable

    property source_channel : String
    property extract : String
    property store : String
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
    property break : Bool? = false
    property capture : CaptureConfig?
    property retrieve : RetrieveConfig?
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

      opts = Agent::Executor::Options.new
      opts.skip(action_config.skip.not_nil!) if action_config.skip
      opts.break(action_config.break.not_nil!) if action_config.break
      executor.when(action_config.when, handler, opts)
    end

    executor
  end

  def self.from_file(yaml_path : String) : Agent::Executor
    yaml_content = File.read(yaml_path)
    from_yaml(yaml_content)
  end
end
