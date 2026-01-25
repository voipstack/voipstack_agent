require "./agent"
require "option_parser"
require "colorize"
require "log"
require "freeswitch-esl"

COMPILE_GIT_REV       = {{ env("COMPILE_GIT_REV") || "HEAD" }}
COMPILE_TIME          = {{ env("COMPILE_TIME") }}
COMPILE_SHARD_VERSION = {{ env("COMPILE_SHARD_VERSION") }}

Log.setup_from_env(default_level: Log::Severity::Info)

ENV["VOIPSTACK_AGENT_SOFTSWITCH_URL"] ||= ""
ENV["VOIPSTACK_AGENT_PRIVATE_KEY_PEM_PATH"] ||= "voipstack_agent.key"
ENV["VOIPSTACK_AGENT_EXIT_ON_MINIMAL_MODE"] ||= "true"
ENV["VOIPSTACK_AGENT_COLLECTOR_LIMIT_QUEUE"] ||= (1024*1024).to_s
ENV["VOIPSTACK_AGENT_COLLECTOR_TICK_SECONDS"] ||= "2"
ENV["VOIPSTACK_AGENT_SOFTSWITCH_CONFIG_PATH"] ||= nil
ENV["VOIPSTACK_AUDIO_FORK_SIP_HOST"] ||= "127.0.0.1"
ENV["VOIPSTACK_AUDIO_FORK_SIP_PORT"] ||= "6070"
ENV["VOIPSTACK_AUDIO_FORK_COMMAND_PATH"] ||= ""
ENV["VOIPSTACK_AUDIO_FORK_SIP_PBX"] ||= "localhost:5060"

exit_on_minimal_mode = false || ENV["VOIPSTACK_AGENT_EXIT_ON_MINIMAL_MODE"] == "true"
collector_limit_queue = ENV["VOIPSTACK_AGENT_COLLECTOR_LIMIT_QUEUE"].to_i
softswitch_id = nil
softswitch_url = ENV["VOIPSTACK_AGENT_SOFTSWITCH_URL"]
softswitch_config_path = if ENV.has_key?("VOIPSTACK_AGENT_SOFTSWITCH_CONFIG_PATH")
                           ENV["VOIPSTACK_AGENT_SOFTSWITCH_CONFIG_PATH"]
                         else
                           nil
                         end
base_action_url = "https://endpoint.voipstack.io"
block_size = 128
audio_fork_sip_host = ENV["VOIPSTACK_AUDIO_FORK_SIP_HOST"]
audio_fork_sip_port = ENV["VOIPSTACK_AUDIO_FORK_SIP_PORT"].to_i
audio_fork_command_path = ENV["VOIPSTACK_AUDIO_FORK_COMMAND_PATH"]
audio_fork_sip_pbx = ENV["VOIPSTACK_AUDIO_FORK_SIP_PBX"]

collector_timeout = ENV["VOIPSTACK_AGENT_COLLECTOR_TICK_SECONDS"].to_i
event_url = "wss://endpoint.voipstack.io/socket"
action_url = ""
private_key_pem_path = ENV["VOIPSTACK_AGENT_PRIVATE_KEY_PEM_PATH"]

OptionParser.parse do |parser|
  parser.banner = "Usage: agent [arguments]"
  parser.on("-s", "--server-url URL", "Freeswitch SERVER ex: fs://ClueConn@:localhost:8021") { |value| softswitch_url = value }
  parser.on("-c", "--config PATH", "Config PATH YAML") { |value| softswitch_config_path = value }
  parser.on("-p", "--event-url URL", "Event URL") { |value| event_url = value }
  parser.on("-a", "--action-url URL", "Action URL") { |value| action_url = value }
  parser.on("-i", "--softswitch-id ID", "Softswitch ID") { |value| softswitch_id = value }
  parser.on("-b", "--block-size INT", "Block Size") { |value| block_size = value.to_i }
  parser.on("--audio-fork-sip-pbx HOST:PORT", "Audio fork SIP PBX : Indicate the origin PBX") { |value| audio_fork_sip_pbx = value }
  parser.on("--audio-fork-sip-host HOST", "Audio fork SIP host") { |value| audio_fork_sip_host = value }
  parser.on("--audio-fork-sip-port PORT", "Audio fork SIP port") { |value| audio_fork_sip_port = value.to_i }
  parser.on("-v", "--version", "Version") {
    puts "VERSION: #{COMPILE_SHARD_VERSION}"
    puts "GIT REV: #{COMPILE_GIT_REV}"
    puts "TIME: #{COMPILE_TIME}"
    exit 1
  }
  parser.on("-g", "--generate-private-key PATH", "Generate Private Key") { |path|
    pkey = OpenSSL::PKey::RSA.new(1024)
    File.write(path, pkey.to_pem)

    puts "Keys generated successfully".colorize(:green)
    puts "Private key saved to #{path}."
    puts "Register this agent in admin.voipstack.io using the following public key:".colorize(:green)
    puts pkey.public_key.to_pem
    exit 0
  }

  parser.on("-h", "--help", "Help") do
    puts parser
    exit 1
  end
end

config = Agent::Config.new
config.softswitch_url = softswitch_url
config.audio_fork_sip_pbx = audio_fork_sip_pbx
config.audio_fork_sip_host = audio_fork_sip_host
config.audio_fork_sip_port = audio_fork_sip_port
config.audio_fork_command_path = audio_fork_command_path

audio_fork_server = Agent::AudioFork::Server.new(config)

executor = Agent::Executor.new

crypto = Agent::NativeOpenSSL.new(private_key_pem_path: private_key_pem_path)
http_client = Agent::HTTPClient.new(crypto: crypto)

softswitch : Agent::SoftswitchState = find_softswitch_state(softswitch_config_path, config.softswitch.scheme.not_nil!, softswitch_id.not_nil!)
Log.debug { "SOFTSWITCH STATE CREATED" }
web_handler = Agent::WebHandler.new(softswitch: softswitch.software, softswitch_id: softswitch_id.not_nil!, http_client: http_client, timeout: 1.second)
Log.debug { "WEB HANDLER CREATED" }
flusher = Agent::PhoenixWebsocketFlusher.new(url: event_url, softswitch_id: softswitch_id.not_nil!, softswitch: softswitch.software, crypto: crypto)
Log.debug { "FLUSHER CREATED" }
main_collector = Agent::Collector.new(block_size: block_size, timeout: collector_timeout.seconds, flusher: flusher, limit_queue: collector_limit_queue)
Log.debug { "MAIN COLLECTOR CREATED" }
collector = Agent::CollectorOnDemand.new(collector: main_collector)
Log.debug { "COLLECTOR ON DEMAND CREATED" }

# default execute softswitch or http post
if softswitch_config_path
  begin
    yaml_content = File.read(softswitch_config_path.not_nil!)
    executor = Agent::ExecutorYaml.from_yaml(yaml_content) do |action_config|
      case action_config.type
      when "softswitch-interface"
        raise "softswitch-interface requires interface" unless action_config.interface
        raise "softswitch-interface requires command" unless action_config.command
        interface = action_config.interface.not_nil!.clone
        Agent::Executor::SoftswitchInterfaceHandler.new(softswitch: softswitch, command: action_config.command.not_nil!, interface: interface, globals: {
          "audio_fork_sip_host" => config.audio_fork_sip_host,
          "audio_fork_sip_port" => config.audio_fork_sip_port.to_s,
        })
      else
        raise "Unknown action type: #{action_config.type}"
      end
    end
  rescue e
    Log.error { "Failed to parse YAML config: #{e}" }
    exit 1
  end
end
match_softswitch = Agent::ActionMatch.new
match_softswitch["handler"] = "dial"
executor.when(match_softswitch, Agent::Executor::ProxySoftswitchStateHandler.new(softswitch: softswitch))
match_http_post = Agent::ActionMatch.new
match_http_post["handler"] = "http_post"
executor.when(match_http_post, Agent::Executor::ProxyHTTPPostHandler.new(handler: web_handler))

if action_url.empty?
  action_url = base_action_url + "/#{softswitch.software}/#{softswitch.version}"
end
Log.debug { "ACTION URL #{action_url} " }

http_getter = Agent::ActionHTTPGetter.new(url: action_url, softswitch_id: softswitch_id.not_nil!, http_client: http_client)
actions = Agent::ActionRunner.new(getter: http_getter)

softswitch.setup(config, softswitch_config_path)

softswitch.bootstrap.each do |event|
  collector.push(event)
end

latest_heartbeat = Time.utc
minimal_mode = false
if exit_on_minimal_mode
  Log.info { "ENABLED EXIT ON MINIMAL MODE" }
end
spawn name: "minimal mode" do
  loop do
    span = Time.utc - latest_heartbeat
    if minimal_mode == false && span.total_seconds > config.minimal_timeout
      minimal_mode = true
      collector.disable
      if exit_on_minimal_mode
        Log.info { "EXITING BY EXIT ON MINIMAL MODE" }
        exit(-1)
      else
        Log.info { "AGENT ENABLED MINIMAL MODE" }
      end
    elsif minimal_mode == true && span.total_seconds < config.minimal_timeout
      minimal_mode = false
      collector.enable
      # resync pbx state
      softswitch.bootstrap.each do |event|
        collector.push(event)
      end
      Log.info { "AGENT DISABLED MINIMAL MODE" }
    end
    sleep 5.seconds
  end
end

spawn do
  loop do
    actions.execute do |action|
      if action.action == "heartbeat"
        latest_heartbeat = Time.utc
      end

      executor.execute(action).each do |event|
        collector.push(event)
      end
    end

    sleep 1.second
  end
rescue e
  STDERR.puts(e.inspect_with_backtrace)
  Log.fatal { e.inspect_with_backtrace }

  exit 1
end

spawn name: "audio_fork_listen" do
  loop do
    audio_fork_server.listen
    sleep 5.seconds
  end
rescue ex
  STDERR.puts(ex.inspect_with_backtrace)
  Log.fatal { ex.inspect_with_backtrace }

  exit 1
end

loop do
  next_events = softswitch.next_platform_events
  next_events.each do |event|
    collector.push(event)
  end
end

def find_softswitch_state(driver_config_path, schema : String, softswitch_id : String) : Agent::SoftswitchState
  case schema
  when "fs"
    Agent::FreeswitchStateVariantVanilla.new(softswitch_id)
  when "fsfusionpbx"
    Agent::FreeswitchStateVariantFusionPBX.new(softswitch_id)
  when "asterisk"
    Agent::AsteriskState.new(softswitch_id, driver_config_path)
  when "generic+udp+hepv3"
    Agent::UDPGenericHEPv3State.new(softswitch_id, driver_config_path)
  else
    raise "unknown how to handle softswitch of kind #{schema}"
  end
end
