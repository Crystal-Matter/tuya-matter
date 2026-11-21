class TuyaFixture
  KEY = "0123456789abcdef"

  property? on : Bool = false
  property? reject_commands : Bool = false
  getter writes = [] of Bool

  @server = TCPServer.new("127.0.0.1", 0)
  @socket : TCPSocket?
  @done = Channel(Nil).new

  def initialize
    spawn do
      while socket = @server.accept?
        @socket = socket
        begin
          serve(socket)
        rescue IO::Error
          # The client disconnected.
        ensure
          socket.close
          @socket = nil
        end
      end
    ensure
      @done.close
    end
  end

  def port : Int32
    @server.local_address.port
  end

  def close : Nil
    @server.close
    @socket.try(&.close)
    @done.receive?
  end

  private def serve(socket : TCPSocket) : Nil
    loop do
      request = Tuya::Frame.read(socket, Tuya::FrameFormat::CRC, KEY.to_slice)
      code = 0_u32
      payload = Bytes.empty
      case request.command
      when 10
        payload = {dps: {"1" => @on}}.to_json.to_slice
      when 7
        if @reject_commands
          code = 1_u32
        else
          ciphertext = Base64.decode(String.new(request.payload[19..]))
          decoded = Tuya::Crypto.ecb(ciphertext, KEY.to_slice, encrypt: false)
          value = JSON.parse(String.new(decoded))["dps"]["1"].as_bool
          @on = value
          @writes << value
        end
      end
      body = IO::Memory.new
      body.write_bytes(code, IO::ByteFormat::BigEndian)
      body.write(payload)
      frame = Tuya::Frame.new(request.sequence, request.command, body.to_slice)
      socket.write(frame.encode(Tuya::FrameFormat::CRC, KEY.to_slice))
    end
  end
end
