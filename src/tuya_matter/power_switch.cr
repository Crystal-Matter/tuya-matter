module TuyaMatter
  # Commands are acknowledged to Matter after the Tuya device acknowledges them.
  class PowerSwitch < Matter::Cluster::OnOff
    private alias Status = Matter::InteractionModel::Status
    private alias Info = Matter::Cluster::BridgedDeviceBasicInformation

    @client : Tuya::Client?
    @info : Info?
    @last_failure : String?
    @operations = Mutex.new

    def attach(@client : Tuya::Client, info : Info) : Nil
      @info = info
      info.reachable = false
    end

    def on : Status
      write_power(true)
    end

    def off : Status
      write_power(false)
    end

    def toggle : Status
      write_power(nil)
    end

    # Publish the device's physical state without issuing a control command.
    def refresh : Nil
      @operations.synchronize do
        client = @client || return
        report(client.on?)
      rescue error : Tuya::Error | KeyError | IO::Error
        report_failure(error)
      end
    end

    def disconnect : Nil
      @operations.synchronize do
        @client.try(&.close)
        @client = nil
      end
    rescue error : IO::Error
      Log.warn { "Closing Tuya switch endpoint #{endpoint_id.number} failed (#{error.class})" }
    end

    private def write_power(desired : Bool?) : Status
      @operations.synchronize do
        client = @client || return Status.failure
        value = desired.nil? ? !client.on? : desired
        client.on = value
        report(value)
        Status.success
      rescue error : Tuya::DeviceError
        Log.warn { "Tuya switch endpoint #{endpoint_id.number} rejected a command (code #{error.code})" }
        Status.failure
      rescue error : Tuya::Error | KeyError | IO::Error
        report_failure(error)
        Status.failure
      end
    end

    private def report(value : Bool) : Nil
      self.on_off = value
      @info.try(&.reachable=(true))
      @last_failure = nil
    end

    private def report_failure(error : Exception) : Nil
      @info.try(&.reachable=(false))
      message = error.message || error.class.name
      if message != @last_failure
        Log.warn { "Tuya switch endpoint #{endpoint_id.number} is unreachable (#{message})" }
        @last_failure = message
      end
    end
  end
end
