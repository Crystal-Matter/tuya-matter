module TuyaMatter
  # Commands are acknowledged to Matter after the Tuya device acknowledges them.
  class PowerSwitch < Matter::Cluster::OnOff
    private alias Status = Matter::InteractionModel::Status
    private alias Info = Matter::Cluster::BridgedDeviceBasicInformation

    private PROBE_TIMEOUT = 1.5.seconds

    @config : SwitchConfig?
    @client : Tuya::Client?
    @info : Info?
    @last_failure : String?
    @operations = Mutex.new

    def attach(config : SwitchConfig, info : Info) : Nil
      @config = config
      @info = info
      @client = config.version_override.try { |version| config.client(version) }
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
    def refresh(announced_version : Tuya::Version? = nil) : Nil
      @operations.synchronize do
        if client = @client
          report(client.on?)
        elsif config = @config
          detect_protocol(config, announced_version)
        end
      rescue error : Tuya::Error | KeyError | IO::Error
        if error.is_a?(Tuya::ProtocolError) && @config.try(&.version).nil?
          @client.try(&.close)
          @client = nil
        end
        report_failure(error)
      end
    end

    def disconnect : Nil
      @operations.synchronize do
        @client.try(&.close)
        @client = nil
        @config = nil
      end
    rescue error : IO::Error
      Log.warn { "Closing Tuya switch endpoint #{endpoint_id.number} failed (#{error.class})" }
    end

    private def detect_protocol(config : SwitchConfig, announced_version : Tuya::Version?) : Nil
      candidates = Tuya::Version.values.reverse!
      if announced_version
        candidates.delete(announced_version)
        candidates.unshift(announced_version)
      end

      candidates.each do |version|
        state = probe(config, version)
        next if state.nil?

        @client = config.client(version)
        Log.info { "Detected Tuya #{version} for switch endpoint #{endpoint_id.number}" }
        report(state)
        return
      end

      raise Tuya::ProtocolError.new("Could not detect a Tuya protocol that reports the configured power datapoint")
    end

    private def probe(config : SwitchConfig, version : Tuya::Version) : Bool?
      client = config.client(version, timeout: PROBE_TIMEOUT)
      client.on?
    rescue Tuya::Error | KeyError | IO::Error
      nil
    ensure
      client.try(&.close)
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
