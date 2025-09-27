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

      publish_mapping(next_events, conn, @softswitch_id)

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

    def interface_command(command : String, input : Hash(String, String)) : Array(Agent::Event)
      next_events = [] of Agent::Event

      case command
      when "api"
        args = input.map { |key, value| "#{key} #{value}" }.join(" ")
        resp = conn.api(args)
        Log.debug { "[EXECUTOR][FREESWITCH] API command executed: #{command} with args: #{args} -> #{resp}" }
      else
        conn.conn.sendmsg(input["call-uuid"] || nil, command, input, "")
      end

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

    def publish_mapping(next_events, conn, softswitch_id)
    end

    private def events
      @events.not_nil!
    end

    private def conn
      @conn.not_nil!
    end
  end

  class FreeswitchStateVariantFusionPBX < FreeswitchStateVariantVanilla
    def initialize(@softswitch_id : String)
    end

    def publish_mapping(next_events, conn, softswitch_id)
      query = %{select SPLIT_PART(a.agent_contact, '/', 2) as agent, a.call_center_agent_uuid as agent_uuid, q.call_center_queue_uuid as queue_uuid, q.queue_extension || '@' || d.domain_name as queue,  d.domain_name from v_call_center_tiers as t left join v_call_center_agents as a on t.call_center_agent_uuid = a.call_center_agent_uuid left join v_call_center_queues as q on q.call_center_queue_uuid = t.call_center_queue_uuid inner join v_domains as d on t.domain_uuid = d.domain_uuid}
      result = sql(conn, query)

      data = Array(Hash(String, String)).new
      result.each do |row|
        data << {"entity" => "callcenter_agent", "source" => row["agent_uuid"], "ref" => row["agent"]}
        data << {"entity" => "callcenter_queue", "source" => row["queue_uuid"], "ref" => row["queue"]}
      end

      next_events << publish_virtual_event(softswitch_id, "mapping", data.to_json)
    end

    def publish_list_users(next_events, conn, softswitch_id)
      result = sql(conn, "select e.extension, d.domain_name from v_extensions as e inner join v_domains as d  on e.domain_uuid = d.domain_uuid")
      data_users = Array(Hash(String, String)).new
      result.each do |row|
        data_users << {"name" => row["extension"], "id" => row["extension"], "domain" => row["domain_name"]}
      end
      next_events << publish_virtual_event(softswitch_id, "load_users", data_users.to_json)
    end

    def publish_list_callcenter_agents(next_events, conn, softswitch_id)
      query = %{select SPLIT_PART(a.agent_contact, '/', 2) as extension, a.call_center_agent_uuid as agent_uuid, d.domain_name, a.agent_contact from v_call_center_agents as a inner join v_domains as d  on a.domain_uuid = d.domain_uuid}
      result = sql(conn, query)

      data_users = Array(Hash(String, String)).new
      result.each do |row|
        data_users << {"name" => row["extension"], "id" => row["extension"], "domain" => row["domain_name"], "contact" => row["agent_contact"]}
      end
      next_events << publish_virtual_event(softswitch_id, "list_agents", {"response" => data_users}.to_json)
    end

    def publish_list_callcenter_tiers(next_events, conn, softswitch_id)
      query = %{select SPLIT_PART(a.agent_contact, '/', 2) as agent, q.queue_extension || '@' || d.domain_name as queue,  d.domain_name from v_call_center_tiers as t left join v_call_center_agents as a on t.call_center_agent_uuid = a.call_center_agent_uuid left join v_call_center_queues as q on q.call_center_queue_uuid = t.call_center_queue_uuid inner join v_domains as d on t.domain_uuid = d.domain_uuid}
      result = sql(conn, query)

      data = Array(Hash(String, String)).new
      result.each do |row|
        data << {"agent" => row["agent"], "queue" => row["queue"], "domain" => row["domain_name"], "state" => "Ready"}
      end
      next_events << publish_virtual_event(softswitch_id, "list_tiers", {"response" => data}.to_json)
    end

    private def sql(conn, query : String) : Array(Hash(String, String))
      cmd = %{
     local database = require "resources.functions.database"
     local dbh = database.new('system')
     local json = require "resources.functions.lunajson"
     local query = "#{query}"
     local result = {}
     assert(dbh:connected())
     assert(dbh:query(query, function(row)
       table.insert(result, row)
     end))
     dbh:release()
     stream:write(json.encode(result))
     }
      res = conn.api("lua", "~loadstring(\"#{obfuscate(cmd)}\")()")

      if res.starts_with?("-ERR")
        raise "FreeswitchStateVariantFusionPBX SQL error: #{res}"
      elsif res == "{}"
        Array(Hash(String, String)).new
      else
        Array(Hash(String, String)).from_json(res)
      end
    end

    private def obfuscate(script : String) : String
      throw_away = [] of UInt8

      # Get bytes from the script string
      script.each_byte do |byte|
        throw_away << byte
      end

      # Convert bytes to escaped string format
      string_buffer = ""
      throw_away.each do |byte|
        string_buffer += "\\#{byte}"
      end

      # Return the obfuscated loadstring format
      string_buffer
    end
  end
end
