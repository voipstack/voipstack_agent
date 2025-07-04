require "http/server"
require "spec"
require "../src/agent"

struct StubHTTPRequest
  property method, headers, body

  def initialize(@method : String, @headers : HTTP::Headers, @body : String)
  end
end

def http_expect_once(return_response : String)
  close = Channel(StubHTTPRequest).new
  req = Channel(StubHTTPRequest).new
  server = HTTP::Server.new do |context|
    stub_req = StubHTTPRequest.new(
      method: context.request.method,
      headers: context.request.headers,
      body: context.request.body.not_nil!.gets_to_end
    )
    close.send stub_req

    context.response.content_type = "application/json"
    context.response.print return_response
  end

  spawn do
    server.bind_tcp 8080
    server.listen
  end

  spawn do
    request = close.receive
    server.close
    req.send request
  end

  Fiber.yield

  req
end
