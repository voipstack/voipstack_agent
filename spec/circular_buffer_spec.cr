require "./spec_helper"

describe Agent::CircularBuffer do
  it "push" do
    buffer = Agent::CircularBuffer(String).new(3)

    buffer.push("a")
    buffer.push("b")
    buffer.push("c")
    buffer.push("d")
    buffer.to_a.should eq ["d", "a", "b"]

    buffer.push("e")
    buffer.to_a.should eq ["e", "d", "a"]
  end
end
