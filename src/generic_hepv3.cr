require "hep"
require "sip_utils"

module Agent
  class UDPGenericHEPv3State < SoftswitchState
    @events = Channel(HEP::Protocol::PacketHEPv3).new(1024*16)

    def initialize(@softswitch_id : String, driver_config_path = nil)
    end

    def software : String
      "generic"
    end

    def version : String
      "1.0.0"
    end

    def setup(config, driver_config_path = nil)
      udp_server_port = config.softswitch.port.not_nil!
      udp_server_host = config.softswitch.host.not_nil!

      Log.debug { "UDPGenericHEPv3 started on #{udp_server_host}:#{udp_server_port}" }

      spawn(name: "generic_hepv3.udp_server") do
        server = UDPSocket.new
        server.bind(udp_server_host, udp_server_port)
        server.reuse_address = true

        loop do
          message, client = server.receive(8192)
          @events.send(HEP::Protocol.parse(message.to_s))
        end
      rescue e
        STDERR.puts(e.inspect_with_backtrace)
        Log.fatal { e.inspect_with_backtrace }
        exit 1
      end
    end

    def bootstrap : Array(Agent::Event)
      Array(Agent::Event).new
    end

    def handle_action(action : Agent::Action) : Array(Agent::Event)
      Array(Agent::Event).new
    end

    def next_platform_events : Array(Agent::Event)
      next_events = Array(Agent::Event).new

      process(@events.receive, next_events)

      next_events
    end

    private def process(packet : HEP::Protocol::PacketHEPv3, next_events : Array(Agent::Event))
      payload = HEP::Protocol::Chunk::Payload.build(packet).to_s
      capture_id = HEP::Protocol::Chunk::CaptureID.build(packet).to_s
      if SIPUtils::Network::SIP(SIPUtils::Network::SIP::Request).valid?(IO::Memory.new(payload))
        process_request(capture_id, SIPUtils::Network::SIP(SIPUtils::Network::SIP::Request).parse(IO::Memory.new(payload)), next_events)
      else
        process_response(capture_id, SIPUtils::Network::SIP(SIPUtils::Network::SIP::Response).parse(IO::Memory.new(payload)), next_events)
      end
    end

    private def process_request(capture_id, sip_req, next_events : Array(Agent::Event))
      case sip_req.method
      when "INVITE"
        publish_event("generic.call", {
          "call_uuid"   => sip_req.headers["Call-ID"],
          "state"       => "ringing",
          "source"      => sip_req.headers["From"],
          "source_ref"  => sip_req.headers["Contact"],
          "destination" => sip_req.headers["To"],
        }, next_events)
      when "REGISTER"
        if sip_req.headers["Expires"] == "0"
          publish_event("generic.unregister", {
            "sip_H-Contact" => sip_req.headers["Contact"],
          }, next_events)
        else
          publish_event("generic.register", {
            "sip_H-Contact" => sip_req.headers["Contact"],
          }, next_events)
        end
      when "BYE"
        publish_event("generic.call_state", {
          "call_uuid" => sip_req.headers["Call-ID"],
          "state"     => "hangup",
        }, next_events)
      end
    end

    private def process_response(capture_id, sip_res, next_events : Array(Agent::Event))
      if sip_res.status_code && sip_res.headers["CSeq"].includes?("INVITE")
        publish_event("generic.call_state", {
          "call_uuid" => sip_res.headers["Call-ID"],
          "state"     => "answered",
        }, next_events)
      end
    end

    private def publish_event(name, response, next_events : Array(Agent::Event))
      payload = Agent::Payload.new(payload: {
        "Event-Name"           => "VIRTUAL",
        "Event-Date-Timestamp" => Time.utc.to_unix_ms.to_s,
        "Virtual-Name"         => name,
      }.merge(response).to_json)

      next_events << Agent::Event.new(
        softswitch: software,
        softswitch_id: @softswitch_id.not_nil!,
        timestamp: Time.utc,
        encoding: "json",
        data: payload.payload,
        signature: payload.signature
      )
    end
  end
end
