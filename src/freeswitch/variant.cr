module Agent
  class FreeswitchStateVariantVanilla < SoftswitchState
    @events : Channel(Freeswitch::ESL::Event)? = nil
    @conn : Freeswitch::ESL::Inbound? = nil

    def initialize(@softswitch_id : String)
    end

    def software : String
      "freeswitch"
    end

    def version : String
      "1.10"
    end

    def setup(config : Agent::Config, driver_config_path : String?)
      @conn = Freeswitch::ESL::Inbound.new(config.softswitch.host.not_nil!,
        config.softswitch.port.not_nil!,
        config.softswitch.password.not_nil!)
      if !conn.connect(1.second)
        raise "freeswitch: fails to login"
      else
        conn.set_events "CHANNEL_CREATE CHANNEL_CALLSTATE HEARTBEAT CUSTOM sofia::register sofia::expire sofia::unregister callcenter::info"

        @events = conn.events

        puts "freeswitch: connected"
      end
    end

    def bootstrap : Array(Agent::Event)
      next_events = [] of Agent::Event

      # order is important don't change
      # first synchronization
      publish_list_users(next_events, conn, @softswitch_id)
      publish_list_registrations(next_events, conn, @softswitch_id)
      publish_list_callcenter_agents(next_events, conn, @softswitch_id)
      publish_list_callcenter_queues(next_events, conn, @softswitch_id)
      publish_list_callcenter_tiers(next_events, conn, @softswitch_id)

      publish_list_calls(next_events, conn, @softswitch_id)
      # must be after calls to override the current calls
      publish_list_callcenter_members(next_events, conn, @softswitch_id)

      next_events
    end

    def handle_action(action : Agent::Action) : Array(Agent::Event)
      next_events = [] of Agent::Event

      case action.action
      when "heartbeat"
        Log.debug { "ACTION #{action}" }

        heartbeat(next_events)
      else
        execute_action_as_dialplan(action, "action", "voipstack")
      end

      next_events << Agent::Notification.action_response_notification(software, @softswitch_id, action.app_id, action.id, "Succesfully")

      next_events
    end

    def heartbeat(next_events)
      publish_list_users(next_events, conn, @softswitch_id)
      publish_list_registrations(next_events, conn, @softswitch_id)
      publish_list_callcenter_agents(next_events, conn, @softswitch_id)
      publish_list_callcenter_queues(next_events, conn, @softswitch_id)
      publish_list_callcenter_tiers(next_events, conn, @softswitch_id)
    end

    def next_platform_events : Array(Agent::Event)
      next_events = [] of Agent::Event
      event = events.receive

      if !event.message.has_key?("Virtual-Name")
        payload = Agent::Payload.new(payload: event.message.to_json)
        if payload.payload.size > 0
          Log.debug { "Sending Payload: #{payload.payload}$$$" }
          next_events <<
            Agent::Event.new(
              softswitch: "freeswitch",
              softswitch_id: @softswitch_id,
              timestamp: Time.utc,
              encoding: "json",
              data: payload.payload,
              signature: payload.signature
            )
        end
      end

      Log.debug { "Freeswitch Event: #{event.headers.to_json} -> #{event.message.to_json}" }

      if event.message.has_key?("Virtual-Name") && event.message.has_key?("Event-Name") && event.message["Event-Name"] == "CUSTOM"
        Log.debug { "Freeswitch Virtual Event: #{event.message["Event-Name"]}" }
        next_events << publish_virtual_event(@softswitch_id, event.message["Virtual-Name"], event.message["Response"])
      end

      # freeswitch change to Standby the other tiers
      if event.message["Event-Name"]? == "CUSTOM" && event.message["Event-Subclass"]? == "callcenter::info" && ["members-count", "bridge-agent-start", "bridge-agent-end", "bridge-agent-fail"].includes?(event.message["CC-Action"]?)
        publish_list_callcenter_tiers(next_events, conn, @softswitch_id)
      end

      next_events
    end

    def publish_list_calls(next_events, conn, softswitch_id)
      resp = conn.api("show detailed_calls as json")
      next_events << publish_virtual_event(softswitch_id, "list_calls", resp)
    end

    def publish_list_users(next_events, conn, softswitch_id)
      resp = conn.api("list_users")
      next_events << publish_virtual_event(softswitch_id, "list_users", resp)
    end

    def publish_list_registrations(next_events, conn, softswitch_id)
      resp = conn.api("show registrations as json")
      next_events << publish_virtual_event(softswitch_id, "list_registrations", resp)
    end

    def publish_list_callcenter_queues(next_events, conn, softswitch_id)
      resp = conn.api("json {\"command\": \"callcenter_config\", \"format\": \"pretty\", \"data\": {\"arguments\":\"queue list\"}}")
      next_events << publish_virtual_event(softswitch_id, "list_queues", resp)
    end

    def publish_list_callcenter_agents(next_events, conn, softswitch_id)
      resp = conn.api("json {\"command\": \"callcenter_config\", \"format\": \"pretty\", \"data\": {\"arguments\":\"agent list\"}}")
      next_events << publish_virtual_event(softswitch_id, "list_agents", resp)
    end

    def publish_list_callcenter_tiers(next_events, conn, softswitch_id)
      resp = conn.api("json {\"command\": \"callcenter_config\", \"format\": \"pretty\", \"data\": {\"arguments\":\"tier list\"}}")
      next_events << publish_virtual_event(softswitch_id, "list_tiers", resp)
    end

    def publish_list_callcenter_members(next_events, conn, softswitch_id)
      resp = conn.api("json {\"command\": \"callcenter_config\", \"format\": \"pretty\", \"data\": {\"arguments\":\"member list\"}}")
      next_events << publish_virtual_event(softswitch_id, "list_members", resp)
    end

    def execute_action_as_dialplan(action, destination_number, destination_context)
      inputs = action.arguments.map { |key, value| "voipstack_action_input_#{key}=#{value}" }.join(",")

      origination_str = "{voipstack_action=#{action.action},#{inputs}}loopback/#{destination_number}/#{destination_context}/XML hangup"
      resp = conn.api("originate", origination_str)

      Log.debug { "EXECUTED ACTION AS DIALPLAN  #{origination_str} -> #{resp}" }
    end

    def publish_virtual_event(softswitch_id, name, response)
      payload = Agent::Payload.new(payload: {
        "Event-Name"   => "VIRTUAL",
        "Virtual-Name" => name,
        "Response"     => response,
      }.to_json
      )
      Log.debug { "Sending Payload: #{payload.payload}$$$" }

      Agent::Event.new(
        softswitch: "freeswitch",
        softswitch_id: softswitch_id.not_nil!,
        timestamp: Time.utc,
        encoding: "json",
        data: payload.payload,
        signature: payload.signature
      )
    end

    private def events
      @events.not_nil!
    end

    private def conn
      @conn.not_nil!
    end
  end

  class FreeswitchStateVariantFusionPBX < SoftswitchState
    # IDEAS
    # freeswitch@9314505bc27a> lua ~loadstring("api=freeswitch.API();resp=api:executeString('uptime')")() stream:write(resp)

    def initialize(@softswitch_id : String)
    end

    def setup(config : Agent::Config, driver_config_path : String?)
    end

    def bootstrap : Array(Agent::Event)
      [] of Agent::Event
    end

    def handle_action(action : Agent::Action) : Array(Agent::Event)
      [] of Agent::Event
    end

    def next_platform_events : Array(Agent::Event)
      [] of Agent::Event
    end

    def software : String
      "freeswitch"
    end

    def version : String
      "1.10"
    end
  end
end
