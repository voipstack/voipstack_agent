module Agent
  class CircularBuffer(T)
    include Indexable::Mutable(T)

    def initialize(@size : Int32)
      @full = false
      @buffer = Deque(T).new(@size)
    end

    def size : Int32
      @buffer.size
    end

    def push(value : T)
      if @buffer.size + 1 > @size
        @buffer.pop
        @buffer.unshift value
      else
        @buffer.push value
      end
    end

    def unsafe_fetch(index : Int) : T
      @buffer.unsafe_fetch(index)
    end

    def unsafe_put(index : Int, value : T)
      @buffer.unsafe_put(index, value)
    end
  end
end
