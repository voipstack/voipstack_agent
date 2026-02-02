require "socket"
require "log"

module Heartbeat
  HEARTBEAT_INTERVAL_ENV = "HEARTBEAT_INTERVAL"
  HEARTBEAT_TIMEOUT_ENV  = "HEARTBEAT_TIMEOUT"
  HEARTBEAT_RETRIES_ENV  = "HEARTBEAT_RETRIES"

  DEFAULT_INTERVAL = 5.seconds
  DEFAULT_TIMEOUT  = 3.seconds
  DEFAULT_RETRIES  = 3

  Log = ::Log.for("heartbeat")

  class Server
    @server : TCPServer
    @failure_count : Int32 = 0

    @heartbeat_port : Int32

    getter :heartbeat_port

    def initialize
      @heartbeat_port = find_free_port
      @server = TCPServer.new(@heartbeat_port)
      Log.info { "Heartbeat server listening on port #{@server.local_address.port}" }
    end

    def start : Nil
      spawn(name: "heartbeat-server") do
        loop do
          begin
            client = @server.accept?
            break unless client
            handle_client(client)
          rescue IO::Error
            break
          rescue ex
            Log.error(exception: ex) { "Error accepting heartbeat connection" }
          end
        end
      end
    end

    private def find_free_port
      addr = TCPServer.new("127.0.0.1", 0)
      port = addr.local_address.port
      addr.close
      port
    end

    private def handle_client(client : TCPSocket) : Nil
      spawn do
        begin
          request = client.gets
          if request && request.strip == "HEARTBEAT"
            client.puts "OK"
          else
            client.puts "INVALID"
          end
        rescue ex
          Log.debug(exception: ex) { "Error handling heartbeat client" }
        ensure
          client.close
        end
      end
    end
  end

  class Client
    @failure_count : Int32 = 0
    @interval = 100.milliseconds
    @timeout = 3.seconds
    @retries = 3

    def initialize(@heartbeat_port : Int32)
    end

    def start : Nil
      spawn(name: "heartbeat-client") do
        loop do
          sleep @interval
          check_heartbeat
        end
      end
      Log.info { "Heartbeat client started, checking parent every #{@interval}" }
    end

    private def check_heartbeat : Nil
      begin
        socket = TCPSocket.new("127.0.0.1", @heartbeat_port, @timeout)
        begin
          socket.puts "HEARTBEAT"
          response = socket.gets
          if response && response.strip == "OK"
            @failure_count = 0
            return
          end
        ensure
          socket.close
        end
      rescue IO::Error
        Log.debug { "Heartbeat connection failed" }
      rescue ex
        Log.debug { "Heartbeat error: #{ex.message}" }
      end

      @failure_count += 1
      Log.warn { "Heartbeat failure #{@failure_count}/#{@retries}" }

      if @failure_count >= @retries
        Log.error { "Parent heartbeat timeout, terminating child process" }
        Process.exit(1)
      end
    end
  end
end
