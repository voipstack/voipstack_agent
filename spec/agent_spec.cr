require "./spec_helper"

class StubFlusher < Agent::Flusher
  getter :n_events

  def initialize
    @n_events = 0
  end

  def flush(events) : Nil
    @n_events = events.size

    nil
  end
end

describe Agent do
  crypto = Agent::DumbOpenSSL.new

  it "flush collected events" do
    flusher = StubFlusher.new
    collector = Agent::Collector.new(
      block_size: 3,
      flusher: flusher,
      timeout: 30.seconds
    )

    collector.push(
      Agent::Event.new(
        softswitch: "freeswitch",
        softswitch_id: "123",
        timestamp: Time.utc,
        encoding: "raw",
        data: "abc"
      )
    )
    flusher.n_events.should eq 0

    collector.push(
      Agent::Event.new(
        softswitch: "freeswitch",
        softswitch_id: "123",
        timestamp: Time.utc,
        encoding: "raw",
        data: "abc"
      )
    )
    flusher.n_events.should eq 0

    collector.push(
      Agent::Event.new(
        softswitch: "freeswitch",
        softswitch_id: "123",
        timestamp: Time.utc,
        encoding: "raw",
        data: "abc"
      )
    )
    flusher.n_events.should eq 3
  end

  it "POST to server" do
    events = Agent::Events.new
    events.push(Agent::Event.new(
      softswitch: "test",
      softswitch_id: "123",
      timestamp: Time.utc,
      encoding: "raw",
      data: "output"
    ))
    events.push(Agent::Event.new(
      softswitch: "test",
      softswitch_id: "123",
      timestamp: Time.utc,
      encoding: "raw",
      data: "output2"
    ))

    http_mock = http_expect_once "OK"
    http_client = Agent::HTTPClient.new(crypto: crypto)
    flusher = Agent::HTTPFlusher.new("http://localhost:8080", "123", http_client: http_client)
    flusher.flush(events)

    req = http_mock.receive
    req.method.should eq "POST"
    req.headers["content-type"].should eq "application/json"
    req.body.should eq "{\"events\":[{\"softswitch\":\"test\",\"softswitch_id\":\"123\",\"encoding\":\"raw\",\"data\":\"output\",\"signature\":\"not implemented\"},{\"softswitch\":\"test\",\"softswitch_id\":\"123\",\"encoding\":\"raw\",\"data\":\"output2\",\"signature\":\"not implemented\"}]}"
  end
end
