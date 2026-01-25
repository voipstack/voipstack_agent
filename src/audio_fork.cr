module Agent::AudioFork
  Log = ::Log.for("voipstack_audio_fork")

  class WebsocketMediaDumper < VoipstackAudioFork::MediaDumper
    def initialize
      @jitter_buffers = Hash(String, VoipstackAudioFork::JitterBuffer).new
    end

    def start(session_id, context : Hash(String, String))
      Log.info { "Starting websocket media dump for session #{session_id}: #{context.inspect}" }

      url = context["X-VOIPSTACK-STREAM-IN-URL"]?
      unless url
        Log.warn { "No X-VOIPSTACK-STREAM-IN-URL in context for session #{session_id}" }
        return
      end

      Log.info { "Websocket URL for session #{session_id}: #{url}" }
      ws = HTTP::WebSocket.new(URI.parse(url))
      writer = VoipstackAudioFork::WebsocketJitterWriter.new(ws)
      jitter_buffer = VoipstackAudioFork::JitterBuffer.new(writer, write_full_packet: true)
      @jitter_buffers[session_id] = jitter_buffer

      spawn do
        ws.run
      rescue ex
        Log.error(exception: ex) { "Websocket error for session #{session_id}" }
      end
    end

    def dump(session_id, data : Bytes)
      Log.debug { "Dumping data for session #{session_id} to websocket" }
      jitter_buffer = @jitter_buffers[session_id]?
      jitter_buffer.try(&.write(data))
    end

    def stop(session_id)
      Log.info { "Stopping websocket media dump for session #{session_id}" }
      if jitter_buffer = @jitter_buffers[session_id]?
        jitter_buffer.writer.close
        @jitter_buffers.delete(session_id)
      end
    end
  end

  class Server
    def initialize(@config : Agent::Config, @softswitch_url : String)
      @server = VoipstackAudioFork::Server.new
      @media_dumper = WebsocketMediaDumper.new
    end

    def listen : Nil
      Log.info { "Starting audio fork server with host=#{@config.audio_fork_sip_host} port=#{@config.audio_fork_sip_port}" }

      pbx_uri = URI.parse(@softswitch_url)
      pbx_host = pbx_uri.host.not_nil!
      pbx_port = pbx_uri.port.not_nil!

      address = @server.bind_pair(@config.audio_fork_sip_host, @config.audio_fork_sip_port, pbx_host, pbx_port)
      @server.attach_dumper(@media_dumper)

      Log.info { "Audio fork server listening on #{address}" }

      @server.listen

      @started = true
    end
  end
end
