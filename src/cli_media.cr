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

OptionParser.parse do |parser|
  parser.banner = "Usage: voipstack_audio_fork [options]"

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

  parser.on("-h", "--help", "Display this help message") do
    puts parser
    exit
  end
end

class VoipstackWebsocketMediaDumper < VoipstackAudioFork::MediaDumper
  Log = ::Log.for("voipstack_audio_fork::cli::WebsocketMediaDumper")

  def initialize
    @jitter_buffers = Hash(String, VoipstackAudioFork::JitterBuffer).new
  end

  def start(session_id, context : Hash(String, String))
    Log.info { "Starting websocket media dump for session #{session_id} : #{context.inspect}" }

    url = render_websocket_url(context)

    Log.info { "Voipstack WebSocket URL: #{url}" }
    ws = HTTP::WebSocket.new(URI.parse(url))
    writer = VoipstackAudioFork::WebsocketJitterWriter.new(ws)
    jitter_buffer = VoipstackAudioFork::JitterBuffer.new(writer, write_full_packet: true)
    @jitter_buffers[session_id] = jitter_buffer

    spawn do
      ws.run
    rescue ex
      Log.error(exception: ex) { "Voipstack WebSocket error for session #{session_id}" }
    end
  end

  def dump(session_id, data : Bytes)
    jitter_buffer = @jitter_buffers[session_id]?
    jitter_buffer.try(&.write(data))
  end

  def stop(session_id)
    Log.info { "Stopping Voipstack WebSocket media dump for session #{session_id}" }
    @jitter_buffers.delete(session_id)
  end

  private def render_websocket_url(context : Hash(String, String))
    return context["X-VOIPSTACK-STREAM-IN-URL"].not_nil!
  end
end

audio_fork = VoipstackAudioFork::Server.new
media_dumper = VoipstackWebsocketMediaDumper.new

address = audio_fork.bind_pair(listen_host, listen_port, pbx_host, pbx_port)
audio_fork.attach_dumper(media_dumper)
Log.info { "Listening on #{address}" }

Log.info { "Starting heartbeat client for parent monitoring" }
heartbeat_client = Heartbeat::Client.new(heartbeat_port.not_nil!)
heartbeat_client.start

audio_fork.listen
