require "json"
require "yaml"
require "asterisk-ami"
require "log"

module Agent
  class AsteriskState < SoftswitchState
    class AsteriskRequest
      def initialize(url : String)
        @uri = URI.parse(url)
      end

      def connect(timeout = 5.seconds)
        ari("/asterisk/info") { |r, s| s }
      end

      def endpoints
        ari("/endpoints") { |r, s|
          raise "fails to get endpoints" unless s
          r
        }
      end

      def ari(action, method = "GET", &)
        cmd = "curl --fail-early -s -u #{@uri.user.not_nil!}:#{@uri.password.not_nil!} -X #{method} http://#{@uri.host.not_nil!}:#{@uri.port.not_nil!}/ari#{action}"
        Log.debug { "ARI: executing #{cmd}" }
        res = `#{cmd}`
        Log.debug { "ARI: response #{res}" }

        yield res, $?.success?
      end
    end

    class Config
      include YAML::Serializable

      property ari_url : String

      def self.from_file(path : String)
        self.from_yaml(File.read(path))
      end
    end

    @conn : Asterisk::Ami::Inbound? = nil
    @events = Channel(Asterisk::Event).new(1024*16)

    def initialize(@softswitch_id : String, driver_config_path = nil)
    end

    def software : String
      "asterisk"
    end

    def version : String
      "1.14"
    end

    def setup(config, driver_config_path = nil)
      if driver_config_path.nil?
        raise "asterisk requires configuration file"
      end
      driver_config = Config.from_file(driver_config_path.not_nil!)
      @asterisk = AsteriskRequest.new(driver_config.ari_url)
      if !@asterisk.not_nil!.connect(1.second)
        raise "asterisk: fails to connecto to ari using #{driver_config.ari_url}"
      end

      @conn = Asterisk::Ami::Inbound.new(
        config.softswitch.host.not_nil!,
        config.softswitch.port.not_nil!,
        config.softswitch.user.not_nil!,
        config.softswitch.password.not_nil!)

      if !conn.connect(1.second, read_timeout: 10.minutes)
        raise "asterisk: fails to login"
      else
        spawn name: "asterisk: events" do
          conn.pull_events do |event|
            @events.send(event)
          end
        rescue ex
          STDERR.puts ex.inspect_with_backtrace
          exit 1
        end

        puts "asterisk: connected"
      end
    end

    def bootstrap : Array(Agent::Event)
      next_events = [] of Agent::Event

      publish_list_endpoints(next_events)
      publish_list_calls(next_events)
      next_events << publish_virtual_event(
        @softswitch_id,
        "QueueStatus",
        conn.request(Asterisk::Action.new(
          "QueueStatus",
          UUID.v4.hexstring
        )).first.not_nil!.message.to_json)

      next_events
    end

    def handle_action(action : Agent::Action) : Array(Agent::Event)
      Array(Agent::Event).new
    end

    def next_platform_events : Array(Agent::Event)
      next_events = Array(Agent::Event).new

      event = @events.receive
      Log.debug { "ASTERISK EVENT: #{event.message.to_json}" }
      payload = Agent::Payload.new(payload: event.message.to_json)

      next_events <<
        Agent::Event.new(
          softswitch: "asterisk",
          softswitch_id: @softswitch_id,
          timestamp: Time.utc,
          encoding: "json",
          data: payload.payload,
          signature: payload.signature
        )
      next_events
    end

    private def conn
      @conn.not_nil!
    end

    private def publish_list_endpoints(next_events)
      resp = @conn.not_nil!.request(Asterisk::Action.new("PJSIPShowEndpoints", UUID.v4.hexstring))

      r = JSON.build do |json|
        json.array do
          resp.each do |event|
            next if event.get("ObjectType", "") != "endpoint"

            # skip trunks or carriers
            if event.get("Auths", "") == "" && event.get("OutboundAuths", "") != ""
              next
            end

            json.start_object
            json.field("technology", "PJSIP")
            json.field("resource", event.get("ObjectName", ""))
            json.field("state", event.get("DeviceState", "").downcase == "unavailable" ? "offline" : "online")
            json.end_object
          end
        end
      end.to_s

      next_events << publish_virtual_event(@softswitch_id, "ari.endpoints", r)
    end

    private def publish_list_calls(next_events)
      @asterisk.not_nil!.ari("/channels") do |r, success?|
        unless success?
          Log.error { "Asterisk: fails to gen endpoints: #{r}" }
          next
        end

        next_events << publish_virtual_event(@softswitch_id, "ari.channels", r)
      end
    end

    private def publish_virtual_event(softswitch_id, name, response)
      payload = Agent::Payload.new(payload: {
        "Event"                => "VIRTUAL",
        "Event-Date-Timestamp" => Time.utc.to_unix_ms.to_s,
        "Virtual-Name"         => name,
        "Response"             => response,
      }.to_json
      )
      Log.debug { "Sending Payload: #{payload.payload}$$$" }

      Agent::Event.new(
        softswitch: "asterisk",
        softswitch_id: softswitch_id.not_nil!,
        timestamp: Time.utc,
        encoding: "json",
        data: payload.payload,
        signature: payload.signature
      )
    end
  end
end
