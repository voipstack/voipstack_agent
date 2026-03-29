require "json"
require "yaml"
require "asterisk-ami"
require "log"

module Agent
  class AsteriskState < SoftswitchState
    alias CapturePromise = {promise: Channel(Asterisk::Event), event_name: String, extract_field: String, match: Hash(String, String)?}
    
    @conn : Asterisk::Ami::Inbound? = nil
    @events = Channel(Asterisk::Event).new(1024*16)
    @capture_promises : Hash(String, CapturePromise) = {} of String => CapturePromise

    def initialize(@softswitch_id : String, driver_config_path = nil)
    end

    def software : String
      "asterisk"
    end

    def version : String
      "1.14"
    end

      EVENTS_TO_PROCESS = %w[
      VIRTUAL
      Newchannel
      Newstate
      DeviceStateChange
      Hangup
      QueueParams
      QueueMember
      AgentConnect
      AgentComplete
      AgentCalled
      AgentRingNoAnswer
      QueueStatus
      OriginateResponse
    ]

    def setup(config, driver_config_path = nil)
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
            # Process capture events first
            process_capture_event(event)

            next if !EVENTS_TO_PROCESS.includes?(event.get("Event", ""))
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

      publish_list_chan_sip_endpoints(next_events)
      publish_list_pjsip_endpoints(next_events)
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

    def interface_command(command : String, input : Hash(String, String)) : Array(Agent::Event)
      next_events = [] of Agent::Event

      req = Asterisk::Action.new(
        command,
        UUID.v4.hexstring,
        header: input
      )
      resp = conn.request(req)
      Log.debug { "[ASTERISK] interface_command request: #{req.inspect}" }
      Log.debug { "[ASTERISK] interface_command response: #{resp.inspect}" }

      next_events
    end

    def handle_action(action : Agent::Action) : Array(Agent::Event)
      next_events = [] of Agent::Event

      case action.action
      when "heartbeat"
        heartbeat(next_events)
      else
        execute_action_as_dialplan(action, "action", "voipstack")
      end

      next_events
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

    private def execute_action_as_dialplan(action, destination_number, destination_context)
      variables = action.arguments.map { |k, v| ["voipstack_action_input_#{k}", v] }.to_h
      variables["voipstack_action"] = action.action

      conn.request(Asterisk::Action.new(
        "Originate", UUID.v4.hexstring,
        header: {
          "Context"  => destination_context,
          "Exten"    => destination_number,
          "Priority" => "1",
          "Channel"  => "Local/#{destination_number}@#{destination_context}",
          "CallerID" => "voipstack-action",
        },
        variables: variables
      )).tap do |response|
        Log.debug { "ASTERISK RESPONSE: #{response.inspect}" }
      end
    end

    private def heartbeat(next_event)
    end

    private def publish_list_chan_sip_endpoints(next_events)
      resp = @conn.not_nil!.request(Asterisk::Action.new("SIPpeers", UUID.v4.hexstring))

      # emulate ari response
      r = JSON.build do |json|
        json.array do
          resp.each do |event|
            next if event.get("Event", "") != "PeerEntry"

            json.start_object
            json.field("technology", "SIP")
            json.field("resource", event.get("ObjectName", ""))
            json.field("state", event.get("Status", "").downcase.includes?("OK") || event.get("Status", "").downcase == "unmonitored" ? "online" : "offline")
            json.field("creationtime", Time::Format::ISO_8601_DATE_TIME.format(Time.utc))
            json.end_object
          end
        end
      end.to_s

      next_events << publish_virtual_event(@softswitch_id, "ari.endpoints", r)
    end

    private def publish_list_pjsip_endpoints(next_events)
      resp = @conn.not_nil!.request(Asterisk::Action.new("PJSIPShowEndpoints", UUID.v4.hexstring))

      # emulate ari response
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
            json.field("creationtime", Time::Format::ISO_8601_DATE_TIME.format(Time.utc))
            json.end_object
          end
        end
      end.to_s

      next_events << publish_virtual_event(@softswitch_id, "ari.endpoints", r)
    end

    private def publish_list_calls(next_events)
      resp = @conn.not_nil!.request(Asterisk::Action.new("CoreShowChannels", UUID.v4.hexstring))
      # emulate ari response
      r = JSON.build do |json|
        json.array do
          resp.each do |event|
            next if event.get("Event", "") != "CoreShowChannel"
            json.start_object
            json.field("name", event.get("Channel").not_nil!)
            json.field("id", event.get("Uniqueid").not_nil!)
            json.field("state", event.get("ChannelStateDesc").not_nil!)
            json.field("caller") do
              json.start_object
              json.field("number", event.get("CallerIDNum"))
              json.field("name", event.get("CallerIDName"))
              json.end_object
            end
            json.field("dialplan") do
              json.start_object
              json.field("exten", event.get("Exten").not_nil!)
              json.field("context", event.get("Context").not_nil!)
              json.end_object
            end
            json.field("creationtime", Time::Format::ISO_8601_DATE_TIME.format(Time.utc))
            json.end_object
          end
        end
      end.to_s

      next_events << publish_virtual_event(@softswitch_id, "ari.channels", r)
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

    # Capture event by waiting for specific event type
    def capture_event(event_name : String, command : String, input : Hash(String, String), extract_field : String, timeout_ms : Int32 = 30000, match : Hash(String, String)? = nil) : String?
      action_id = "capture-#{UUID.v4.hexstring}"
      input_copy = input.clone
      input_copy["ActionID"] = action_id

      # Create a channel to receive the response
      promise = Channel(Asterisk::Event).new(1)
      @capture_promises[action_id] = {promise: promise, event_name: event_name, extract_field: extract_field, match: match}

      begin
        # Send the command
        req = Asterisk::Action.new(
          command,
          action_id,
          header: input_copy
        )
        conn.request(req)

        # Wait for event with timeout (from YAML config)
        select
        when event = promise.receive
          @capture_promises.delete(action_id)
          return event.get(extract_field)
        when timeout(timeout_ms.milliseconds)
          @capture_promises.delete(action_id)
          Log.error { "[ASTERISK] Timeout waiting for #{event_name} (#{timeout_ms}ms)" }
          return nil
        end
      rescue ex
        @capture_promises.delete(action_id)
        Log.error { "[ASTERISK] Error capturing #{event_name}: #{ex.message}" }
        return nil
      end
    end

    # Set channel variable using AMI SetVar
    def set_channel_var(channel : String, variable : String, value : String)
      req = Asterisk::Action.new(
        "SetVar",
        UUID.v4.hexstring,
        header: {
          "Channel"  => channel,
          "Variable" => variable,
          "Value"    => value,
        }
      )
      conn.request(req)
      Log.debug { "[ASTERISK] Set channel variable: #{variable}=#{value} on #{channel}" }
    end

    # Get channel variable using AMI GetVar
    def get_channel_var(channel : String, variable : String) : String?
      req = Asterisk::Action.new(
        "GetVar",
        UUID.v4.hexstring,
        header: {
          "Channel"  => channel,
          "Variable" => variable,
        }
      )
      resp = conn.request(req)
      
      # Parse response to extract value
      if resp.size > 0
        first = resp.first
        if first && first.get("Response") == "Success"
          return first.get("Value")
        end
      end
      nil
    rescue ex
      Log.error { "[ASTERISK] Error getting channel variable: #{ex.message}" }
      nil
    end

    # Process events and fulfill capture promises
    private def process_capture_event(event : Asterisk::Event)
      event_name = event.get("Event")
      action_id = event.get("ActionID")

      if action_id && @capture_promises.has_key?(action_id)
        promise_data = @capture_promises[action_id]
        if event_name == promise_data[:event_name]
          # Check match conditions if provided
          if match = promise_data[:match]
            all_match = match.all? do |field, expected_value|
              event.get(field) == expected_value
            end
            if all_match
              # Remove from memory and send event
              @capture_promises.delete(action_id)
              promise_data[:promise].send(event)
            else
              # Conditions didn't match - remove from memory to free up resources
              @capture_promises.delete(action_id)
              Log.debug { "[ASTERISK] Capture event #{event_name} did not match conditions: #{match.inspect}, cleaning up" }
            end
          else
            # No match conditions - accept any event
            @capture_promises.delete(action_id)
            promise_data[:promise].send(event)
          end
        end
      end
    end
  end
end
