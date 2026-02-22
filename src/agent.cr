require "digest/sha256"
require "http/client"
require "json"
require "log"
require "crest"
require "freeswitch-esl"
require "phoenixchannels"

module Agent
  VERSION = "0.1.0"

  alias Events = Deque(Event)

  abstract class Flusher
    abstract def flush(events : Events) : Nil
  end

  class Config
    @softswitch_url : String = ""
    @minimal_timeout : Int32 = 300
    @agent_media_sip_host : String = "127.0.0.1"
    @agent_media_sip_port : Int32 = 0
    @agent_media_command_path : String = ""
    @agent_media_sip_pbx : String = ""
    @agent_media_max_sessions : Int32 = 1000

    setter :softswitch_url
    setter :minimal_timeout
    setter :agent_media_sip_host
    setter :agent_media_sip_port
    setter :agent_media_command_path
    setter :agent_media_sip_pbx
    setter :agent_media_max_sessions
    getter :minimal_timeout
    getter :agent_media_sip_host
    getter :agent_media_sip_port
    getter :agent_media_command_path
    getter :agent_media_sip_pbx
    getter :agent_media_max_sessions

    def softswitch
      if @softswitch_url.nil?
        raise "invalid softswitch_url"
      end

      URI.parse(@softswitch_url)
    end
  end

  class HTTPClient
    alias HTTPResponse = Crest::Response

    def initialize(@crypto : Agent::Crypto)
    end

    def post(url, body)
      signature = @crypto.sign(message("POST", url, body))
      Crest.post(url, body, headers: {"content-type" => "application/json", "x-voipstack-signature" => signature})
    end

    def post_json(url, body, timeout : Time::Span = 5.second)
      signature = @crypto.sign(message("POST", url, body))
      Crest.post(url, body, headers: {"content-type" => "application/json", "x-voipstack-signature" => signature}, json: true, read_timeout: timeout, write_timeout: timeout, connect_timeout: timeout).as(HTTPResponse)
    end

    private def message(method, uri, body)
      url = URI.parse uri
      url.scheme = nil
      url.host = nil
      url.port = nil
      "POST#{url.to_s}#{body}"
    end
  end

  class WebHandler
    def initialize(
      @softswitch : String,
      @softswitch_id : String,
      @http_client : HTTPClient,
      @timeout : Time::Span,
    )
    end

    def handle_action(action : Agent::Action) : Array(Agent::Event)
      url = action.handler_arguments["url"]
      resp = @http_client.post_json(url, {
        "id"        => action.id,
        "app_id"    => action.app_id,
        "action"    => action.action,
        "arguments" => action.arguments,
      }, timeout: 1.second)
      resp_body = resp.body.not_nil!
      Log.debug { "WEB HANDLER: handle_action #{action.action} RESPONSE STATUS CODE #{resp.status_code} #{resp_body}" }
      case resp.status_code
      when 200
        [Agent::Notification.action_response_notification_direct(@softswitch, @softswitch_id, action.app_id, action.id, resp_body)]
      else
        [Agent::Notification.action_response_notification(@softswitch, @softswitch_id, action.app_id, action.id, resp_body)]
      end
    rescue ex
      Log.error { "WebHandler #{url} Exception: #{ex.message}" }
      [] of Agent::Event
    end
  end

  class ConsoleFlusher < Flusher
    def initialize(@url : String)
    end

    def flush(events : Events) : Nil
      puts "Flushing #{events.size} events to #{@url}..."
    end
  end

  class PhoenixWebsocketFlusher < Flusher
    @channel : Phoenixchannels::PhoenixChannel(Hash(String, String))

    def initialize(@url : String, @softswitch_id : String, @softswitch : String, @crypto : Agent::Crypto)
      @socket = Phoenixchannels::Socket.new(@url, {"softswitch_id" => [@softswitch_id], "softswitch" => [@softswitch]})
      @socket.install_heartbeat(5.seconds)

      signature = @crypto.sign("WSconnect#{@softswitch_id}")
      @channel = @socket.channel("agent:events", {"softswitch_id" => @softswitch_id, "softswitch" => @softswitch, "signature" => signature})
    end

    def flush(events : Events) : Nil
      payload = encode(events)
      signature = @crypto.sign("WSevents#{@softswitch_id}")
      @channel.push("events", {"events" => payload, "signature" => signature})
      nil
    end

    private def encode(events : Events)
      JSON.build do |json|
        json.array do
          events.each do |event|
            json.object do
              json.field "softswitch", event.softswitch
              json.field "softswitch_id", event.softswitch_id
              json.field "encoding", event.encoding
              json.field "data", event.data
              json.field "signature", event.signature
            end
          end
        end
      end
    end
  end

  class HTTPFlusher < Flusher
    def initialize(@url : String, @softswitch_id : String, @http_client : HTTPClient)
    end

    def flush(events : Events) : Nil
      @http_client.post_json(
        "#{@url}/softswitch/#{@softswitch_id}/events",
        encode(events)
      )

      nil
    end

    private def encode(events : Events)
      JSON.build do |json|
        json.object do
          json.field "events" do
            json.array do
              events.each do |event|
                json.object do
                  json.field "softswitch", event.softswitch
                  json.field "softswitch_id", event.softswitch_id
                  json.field "encoding", event.encoding
                  json.field "data", event.data
                  json.field "signature", event.signature
                end
              end
            end
          end
        end
      end
    end
  end

  class Collector
    def initialize(@block_size : Int32, @timeout : Time::Span, @flusher : Flusher, @limit_queue : Int32 = 1024*1024)
      Log.info { "COLLECTOR BLOCK_SIZE: #{@block_size} LIMIT_QUEUE: #{@limit_queue}" }
      @queue = Events.new
      @last_stamp = Time.utc
    end

    def push(event : Event)
      if @queue.size >= @limit_queue
        raise "Reached max limit of collector #{@limit_queue}. Increase with environment var VOIPSTACK_AGENT_COLLECTOR_LIMIT_QUEUE."
      end

      @queue.push(event)
      try_flush()
    end

    private def try_flush
      span = Time.utc - @last_stamp
      if @queue.size >= @block_size || span.total_milliseconds.to_i > @timeout.milliseconds.to_i
        @last_stamp = Time.utc
        events_to_send = @queue.dup
        @queue.clear
        @flusher.flush(events_to_send)
      end
    end
  end

  class CollectorOnDemand
    def initialize(@collector : Collector)
      @enabled = true
    end

    def enable
      @enabled = true
    end

    def disable
      @enabled = false
    end

    def push(event : Event)
      if @enabled
        @collector.push(event)
      end
    end
  end

  class Payload
    getter :payload

    def initialize(@payload : String)
    end

    def signature
      "not implemented"
    end
  end

  struct Event
    getter :softswitch, :data, :timestamp, :encoding, :signature, :softswitch_id

    def initialize(@softswitch : String, @data : String, @timestamp : Time, @encoding : String, @softswitch_id : String, @signature : String = "not implemented")
    end
  end

  alias ActionVendor = Hash(String, String)
  alias ActionArgument = Hash(String, String)
  alias ActionMatch = Hash(String, String | Hash(String, String))

  struct Action
    getter :id, :app_id, :previous_id, :action, :arguments, :handler_arguments, :vendor

    def initialize(@app_id : String, @id : String, @action : String, @arguments : ActionArgument, @handler : String, @handler_arguments : ActionArgument, @previous_id : String? = nil, @vendor = ActionVendor.new)
      @easy_match = {
        "app_id"            => @app_id,
        "id"                => @id,
        "action"            => @action,
        "handler"           => @handler,
        "previous_id"       => @previous_id,
        "arguments"         => @arguments.to_h,
        "handler_arguments" => @handler_arguments.to_h,
        "vendor"            => @vendor.to_h,
      }
    end

    def match?(match : ActionMatch)
      match.all? do |key, value|
        if value.is_a?(Hash)
          value.all? { |sub_key, sub_value|
            @easy_match.has_key?(key) && @easy_match[key].not_nil!.[sub_key] == sub_value
          }
        else
          @easy_match[key] == value
        end
      end
    end
  end

  alias Actions = Array(Action)

  abstract class ActionGetter
    abstract def fetch : Actions
  end

  class ActionRunner
    @executed_ids : Agent::CircularBuffer(String)

    def initialize(@getter : ActionGetter, @size : Int32 = 1024 * 128)
      @executed_ids = Agent::CircularBuffer(String).new(@size)
    end

    def execute(&)
      @getter.fetch.each do |action|
        if @executed_ids.includes?(action.id)
          next
        end

        Log.debug { "EXECUTING ACTION #{action.inspect}" }

        yield action

        @executed_ids.push(action.id)
      end
    end
  end

  class ActionHTTPGetter < ActionGetter
    def initialize(@url : String, @softswitch_id : String, @http_client : HTTPClient)
    end

    def fetch : Actions
      actions = Actions.new
      url_req = "#{@url}/softswitch/#{@softswitch_id}/actions"

      resp = @http_client.post("#{@url}/softswitch/#{@softswitch_id}/actions", nil)
      Log.debug { "ACTION RESPONSE #{resp.body}" }
      JSON.parse(resp.body)["data"].as_h.not_nil!.["actions"].as_a.map do |action_data|
        arguments = ActionArgument.new
        action_data["arguments"].as_h.not_nil!.each do |k, v|
          arguments[k] = v.as_s? || ""
        end
        handler_arguments = ActionArgument.new
        action_data["handler_arguments"].as_h.not_nil!.each do |k, v|
          handler_arguments[k] = v.as_s? || ""
        end
        vendor = ActionVendor.new
        action_data["vendor"].as_h.not_nil!.each do |k, v|
          vendor[k] = v.as_s? || ""
        end

        Action.new(
          app_id: action_data["app_id"].as_s.not_nil!,
          id: action_data["id"].as_s.not_nil!,
          previous_id: action_data["previous_id"].as_s?,
          action: action_data["action"].as_s.not_nil!,
          arguments: arguments,
          handler: action_data["handler"].as_s.not_nil!,
          handler_arguments: handler_arguments,
          vendor: vendor)
      end
    end
  end

  abstract class SoftswitchState
    abstract def setup(config : Agent::Config, driver_config_path : String?)
    abstract def bootstrap : Array(Agent::Event)
    abstract def interface_command(command : String, input : Hash(String, String)) : Array(Agent::Event)
    abstract def handle_action(action : Agent::Action) : Array(Agent::Event)
    abstract def next_platform_events : Array(Agent::Event)
    abstract def software : String
    abstract def version : String
  end

  class Notification
    def self.action_response_notification(software, softswitch_id, app_id, action_id, message)
      action_response_notification_direct(software, softswitch_id, app_id, action_id, {"type" => "notification", "message" => message}.to_json)
    end

    def self.action_response_notification_direct(software, softswitch_id, app_id, action_id, response)
      payload = Agent::Payload.new(payload: {
        "Event-Name"        => "VIRTUAL",
        "Virtual-Name"      => "action_handler_response",
        "Handler-App-ID"    => app_id,
        "Handler-Action-ID" => action_id,
        "Response"          => response,
      }.to_json)
      Agent::Event.new(
        softswitch: software,
        softswitch_id: softswitch_id,
        timestamp: Time.utc,
        encoding: "json",
        data: payload.payload,
        signature: payload.payload)
    end
  end
end

require "./executor"

require "./freeswitch"
require "./asterisk"
require "./crypto"
require "./circular_buffer"
require "./generic_hepv3"
require "./media_agent"
