module Agent::Media
  Log = ::Log.for("voipstack_agent_media")

  class Server
    def initialize(@config : Agent::Config, @port : Int32)
    end

    private def find_command : String?
      command_path = @config.agent_media_command_path
      if command_path.empty?
        return Process.find_executable("voipstack_agent_media")
      elsif !File::Info.executable?(command_path)
        raise "voipstack_agent_media command at #{command_path} is not executable"
      end
      command_path
    end

    def listen : Nil
      Log.info { "Starting media agent server with host=#{@config.agent_media_sip_host} port=#{@config.agent_media_sip_port} pbx=#{@config.agent_media_sip_pbx} max_sessions=#{@config.agent_media_max_sessions}" }

      pbx_params = @config.agent_media_sip_pbx.split(":")
      pbx_host = pbx_params[0]
      pbx_port = pbx_params[1]

      command = find_command
      args = [
        "--listen", @config.agent_media_sip_host,
        "--port", @config.agent_media_sip_port.to_s,
        "--pbx", "sip://#{pbx_host}:#{pbx_port}",
        "--heartbeat-port", @port.to_s,
      ]

      Log.info { "Spawning audio fork command: #{command} #{args.join(" ")} (max_sessions=#{@config.agent_media_max_sessions})" }

      if command.nil?
        Log.info { "voipstack_agent_media command not found in PATH. Omiting." }
        sleep
        return
      end

      Process.run(command, args: args, output: STDOUT, error: STDERR, env: {
        "LOG_LEVEL"    => "info",
        "MAX_SESSIONS" => @config.agent_media_max_sessions.to_s,
      })
    end
  end
end
