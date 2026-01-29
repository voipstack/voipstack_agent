module Agent::AudioFork
  Log = ::Log.for("voipstack_agent_media")

  class Server
    def initialize(@config : Agent::Config)
    end

    private def find_command : String?
      command_path = @config.audio_fork_command_path
      if command_path.empty?
        return Process.find_executable("voipstack_agent_media")
      elsif !File::Info.executable?(command_path)
        raise "voipstack_agent_media command at #{command_path} is not executable"
      end
      command_path
    end

    def listen : Nil
      Log.info { "Starting audio fork server with host=#{@config.audio_fork_sip_host} port=#{@config.audio_fork_sip_port} pbx=#{@config.audio_fork_sip_pbx}" }

      pbx_params = @config.audio_fork_sip_pbx.split(":")
      pbx_host = pbx_params[0]
      pbx_port = pbx_params[1]

      command = find_command
      args = [
        "--listen", @config.audio_fork_sip_host,
        "--port", @config.audio_fork_sip_port.to_s,
        "--pbx", "sip://#{pbx_host}:#{pbx_port}",
        "--output", "voipstack://",
      ]

      Log.info { "Spawning audio fork command: #{command} #{args.join(" ")}" }

      if command.nil?
        Log.info { "voipstack_agent_media command not found in PATH. Omiting." }
        sleep
        return
      end

      Process.run(command, args: args, output: STDOUT, error: STDERR, env: {"LOG_LEVEL" => "info"})
    end
  end
end
