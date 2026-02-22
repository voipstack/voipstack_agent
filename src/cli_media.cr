require "uri"
require "log"
require "option_parser"
require "sip_utils"
require "http/web_socket"
require "voipstack_audio_fork"
require "./heartbeat"

Log.setup_from_env(default_level: Log::Severity::Debug)

listen_host = "127.0.0.1"
listen_port = 5060
pbx_host = "127.0.0.1"
pbx_port = 5080
heartbeat_port = nil
max_sessions = ENV.fetch("MAX_SESSIONS", "10000").to_i

OptionParser.parse do |parser|
  parser.banner = "Usage: voipstack_agent_media [options]"

  parser.on("-s URL", "--pbx=URL", "PBX URL") do |url|
    pbx_host, pbx_port = URI.parse(url).host.not_nil!, URI.parse(url).port.not_nil!
  end

  parser.on("-l HOST", "--listen=HOST", "Listen host") do |host|
    listen_host = host
  end

  parser.on("-p PORT", "--port=PORT", "Listen port") do |port|
    listen_port = port.to_i
  end

  parser.on("-b PORT", "--heartbeat-port=PORT", "Heartbeat port") do |port|
    heartbeat_port = port.to_i
  end

  parser.on("-m COUNT", "--max-sessions=COUNT", "Maximum concurrent sessions (default: 1000, env: MAX_SESSIONS)") do |count|
    max_sessions = count.to_i
  end

  parser.on("-h", "--help", "Display this help message") do
    puts parser
    exit
  end
end

class VoipstackWebsocketMediaDumper < VoipstackAudioFork::MediaDumper
  Log = ::Log.for("voipstack_audio_fork::cli::WebsocketMediaDumper")

  # Store both jitter buffer and websocket for proper cleanup
  record Session, jitter_buffer : VoipstackAudioFork::JitterBuffer, ws : HTTP::WebSocket

  def initialize(@max_sessions : Int32 = 1_000)
    @sessions = Hash(String, Session).new
    @mutex = Mutex.new
  end

  def start(session_id, context : Hash(String, String))
    begin
      # Check session limit
      current_count = @mutex.synchronize { @sessions.size }
      if current_count >= @max_sessions
        Log.error { "Session limit reached: #{current_count}/#{@max_sessions}" }
        raise "Max sessions limit reached"
      end

      url = render_websocket_url(context)
      raise "Missing X-VOIPSTACK-STREAM-IN-URL header" if url.nil? || url.empty?

      ws = HTTP::WebSocket.new(URI.parse(url))
      writer = VoipstackAudioFork::WebsocketJitterWriter.new(ws)
      jitter_buffer = VoipstackAudioFork::JitterBuffer.new(writer, write_full_packet: true)

      @mutex.synchronize do
        # Clean up existing session if any (shouldn't happen, but be safe)
        if @sessions.has_key?(session_id)
          Log.warn { "Session #{session_id} already exists, cleaning up old session first" }
          old_session = @sessions.delete(session_id)
          old_session.try do |s|
            spawn { close_session_resources(s) }
          end
        end
        @sessions[session_id] = Session.new(jitter_buffer, ws)
      end

      spawn do
        ws.run
      rescue ex
        Log.error(exception: ex) { "Voipstack WebSocket error for session #{session_id}" }
      ensure
        # Clean up session if WebSocket closes unexpectedly
        @mutex.synchronize do
          stop(session_id) if @sessions.has_key?(session_id)
        end
      end
    rescue ex
      Log.error(exception: ex) { "Failed to start WebSocket for session #{session_id}" }
      # Clean up any partial resources
      stop(session_id)
      raise ex
    end
  end

  def dump(session_id, data : Bytes)
    session = @mutex.synchronize { @sessions[session_id]? }
    session.try(&.jitter_buffer.write(data))
  end

  def stop(session_id)
    Log.info { "Stopping Voipstack WebSocket media dump for session #{session_id}" }

    session = @mutex.synchronize { @sessions.delete(session_id) }

    if session
      # Close the jitter buffer writer first to flush any pending data
      begin
        session.jitter_buffer.writer.close
      rescue ex
        Log.warn(exception: ex) { "Error closing jitter buffer writer for session #{session_id}" }
      end
      # Close the WebSocket connection
      begin
        session.ws.close
      rescue ex
        Log.warn(exception: ex) { "Error closing WebSocket for session #{session_id}" }
      end
    end
  end

  # Close all active sessions - useful for graceful shutdown
  def close_all : Nil
    Log.info { "Closing all #{@sessions.size} active sessions" }

    sessions_to_close = @mutex.synchronize do
      sessions = @sessions.values
      @sessions.clear
      sessions
    end

    sessions_to_close.each do |session|
      begin
        session.jitter_buffer.writer.close
      rescue ex
        Log.warn(exception: ex) { "Error closing jitter buffer writer during shutdown" }
      end

      begin
        session.ws.close
      rescue ex
        Log.warn(exception: ex) { "Error closing WebSocket during shutdown" }
      end
    end
  end

  private def close_session_resources(session : Session) : Nil
    begin
      session.jitter_buffer.writer.close
    rescue ex
      Log.warn(exception: ex) { "Error closing jitter buffer writer" }
    end

    begin
      session.ws.close
    rescue ex
      Log.warn(exception: ex) { "Error closing WebSocket" }
    end
  end

  private def render_websocket_url(context : Hash(String, String))
    context["X-VOIPSTACK-STREAM-IN-URL"]?.try(&.to_s)
  end
end

audio_fork = VoipstackAudioFork::Server.new
media_dumper = VoipstackWebsocketMediaDumper.new(max_sessions)

address = audio_fork.bind_pair(listen_host, listen_port, pbx_host, pbx_port)
audio_fork.attach_dumper(media_dumper)
Log.info { "Listening on #{address} (max_sessions=#{max_sessions})" }

# Graceful shutdown handler
Signal::INT.trap do
  Log.info { "Received INT signal, shutting down gracefully..." }
  media_dumper.close_all
  audio_fork.close
  exit(0)
end

Signal::TERM.trap do
  Log.info { "Received TERM signal, shutting down gracefully..." }
  media_dumper.close_all
  audio_fork.close
  exit(0)
end

Log.info { "Starting heartbeat client for parent monitoring" }
heartbeat_client = Heartbeat::Client.new(heartbeat_port.not_nil!)
heartbeat_client.start

audio_fork.listen
