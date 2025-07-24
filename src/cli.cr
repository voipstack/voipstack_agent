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
ENV["VOIPSTACK_AGENT_PRIVATE_KEY_PEM_PATH"] ||= "agent.key"
ENV["VOIPSTACK_AGENT_EXIT_ON_MINIMAL_MODE"] ||= "false"
ENV["VOIPSTACK_AGENT_COLLECTOR_LIMIT_QUEUE"] ||= (1024*1024).to_s
ENV["VOIPSTACK_AGENT_COLLECTOR_TICK_SECONDS"] ||= "2"

exit_on_minimal_mode = false || ENV["VOIPSTACK_AGENT_EXIT_ON_MINIMAL_MODE"] == "true"
collector_limit_queue = ENV["VOIPSTACK_AGENT_COLLECTOR_LIMIT_QUEUE"].to_i
softswitch_id = nil
softswitch_url = ENV["VOIPSTACK_AGENT_SOFTSWITCH_URL"]
softswitch_config_path = nil
base_action_url = "https://endpoint.voipstack.io"
block_size = 128

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

crypto = Agent::NativeOpenSSL.new(private_key_pem_path: private_key_pem_path)
http_client = Agent::HTTPClient.new(crypto: crypto)

softswitch : Agent::SoftswitchState = find_softswitch_state(softswitch_config_path, config.softswitch.scheme.not_nil!, softswitch_id.not_nil!)

web_handler = Agent::WebHandler.new(softswitch: softswitch.software, softswitch_id: softswitch_id.not_nil!, http_client: http_client, timeout: 1.second)

flusher = Agent::PhoenixWebsocketFlusher.new(url: event_url, softswitch_id: softswitch_id.not_nil!, softswitch: softswitch.software, crypto: crypto)
main_collector = Agent::Collector.new(block_size: block_size, timeout: collector_timeout.seconds, flusher: flusher, limit_queue: collector_limit_queue)
collector = Agent::CollectorOnDemand.new(collector: main_collector)

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

      if action.dial?
        softswitch.handle_action(action).each do |event|
          collector.push(event)
        end
      elsif action.http_post?
        web_handler.handle_action(action).each do |event|
          collector.push(event)
        end
      end
    end

    sleep 1.second
  end
rescue e
  STDERR.puts(e.inspect_with_backtrace)
  Log.fatal { e.inspect_with_backtrace }

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
    Agent::FreeswitchState.new(softswitch_id, driver_config_path)
  when "asterisk"
    Agent::AsteriskState.new(softswitch_id, driver_config_path)
  else
    raise "unknown how to handle softswitch of kind #{schema}"
  end
end
