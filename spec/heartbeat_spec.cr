require "./spec_helper"
require "../src/heartbeat"

describe Heartbeat::Server do
  describe "#new" do
    it "binds to specified port" do
      server = Heartbeat::Server.new
      server.should_not be_nil
    end
  end

  describe "#start" do
    it "starts successfully" do
      server = Heartbeat::Server.new
      server.start
    end
  end

  describe "heartbeat response" do
    it "responds with OK to HEARTBEAT request" do
      server = Heartbeat::Server.new
      server.start

      sleep 0.1

      begin
        TCPSocket.open("127.0.0.1", server.heartbeat_port) do |socket|
          socket.puts "HEARTBEAT"
          response = socket.gets
          response.should eq("OK")
        end
      end
    end

    it "responds with INVALID to invalid request" do
      server = Heartbeat::Server.new
      server.start

      sleep 0.1

      begin
        TCPSocket.open("127.0.0.1", server.heartbeat_port) do |socket|
          socket.puts "INVALID"
          response = socket.gets
          response.should eq("INVALID")
        end
      end
    end
  end
end

describe Heartbeat::Client do
  describe "#new" do
    it "creates client with configuration" do
      client = Heartbeat::Client.new(15238)
      client.should_not be_nil
    end
  end

  describe "#start" do
    it "starts successfully" do
      server = Heartbeat::Server.new
      server.start
      sleep 0.1

      begin
        client = Heartbeat::Client.new(server.heartbeat_port)
        client.start
      end
    end
  end

  describe "heartbeat check" do
    it "works with running server" do
      server = Heartbeat::Server.new
      server.start
      sleep 0.1

      begin
        client = Heartbeat::Client.new(server.heartbeat_port)
        client.start
        sleep 0.2
      end
    end
  end
end
