module TuyaMatter
  # Commands are acknowledged to Matter after the Tuya device acknowledges them.
  class PowerSwitch < Matter::Cluster::OnOff
    private alias Status = Matter::InteractionModel::Status
    private alias Info = Matter::Cluster::BridgedDeviceBasicInformation
    private alias ProbeFailures = Hash(String, Array(Tuya::Version))

    private PROBE_TIMEOUT = 1.5.seconds

    @config : SwitchConfig?
    @client : Tuya::Client?
    @info : Info?
    @last_write_failure : String?
    @operations = Mutex.new

    def attach(config : SwitchConfig, info : Info) : Nil
      @config = config
      @info = info
      @client = config.version_override.try { |version| config.client(version) }
      info.reachable = false
      Log.info { "Configured Tuya switch #{switch_description}" }
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
          report(read_power(client))
        elsif config = @config
          detect_protocol(config, announced_version)
        end
      rescue error : Tuya::Error | KeyError | IO::Error
        if error.is_a?(Tuya::ProtocolError) && @config.try(&.version).nil?
          @client = nil
        end
        Log.debug { "Tuya switch #{switch_description} status poll failed. #{failure_message(error)}" }
      ensure
        close_connection(client)
      end
    end

    def disconnect : Nil
      @operations.synchronize do
        close_connection(@client)
        @client = nil
        @config = nil
      end
    end

    private def detect_protocol(config : SwitchConfig, announced_version : Tuya::Version?) : Nil
      candidates = Tuya::Version.values.reverse!
      if announced_version
        candidates.delete(announced_version)
        candidates.unshift(announced_version)
      end

      failures = ProbeFailures.new { |errors, reason| errors[reason] = [] of Tuya::Version }
      candidates.each do |version|
        state = probe(config, version, failures)
        next if state.nil?

        @client = config.client(version)
        Log.info { "Detected Tuya #{version} for switch #{switch_description}" }
        report(state)
        return
      end

      details = failures.map { |reason, versions| "#{reason} (Tuya #{versions.join(", ")})" }.join(" | ")
      raise Tuya::ProtocolError.new("Status probes failed. #{details}")
    end

    private def probe(config : SwitchConfig, version : Tuya::Version, failures : ProbeFailures) : Bool?
      client = config.client(version, timeout: PROBE_TIMEOUT)
      read_power(client)
    rescue error : Tuya::Error | KeyError | IO::Error
      failures[failure_message(error)] << version
      nil
    ensure
      close_connection(client)
    end

    private def read_power(client : Tuya::Client) : Bool
      client.on?
    rescue error : KeyError
      raise error unless @config.try(&.assume_off_when_missing?)

      false
    end

    private def write_power(desired : Bool?) : Status
      @operations.synchronize do
        unless client = @client
          report_write_failure("Tuya protocol is unavailable")
          return Status.failure
        end

        value = desired.nil? ? !read_power(client) : desired
        client.on = value
        report(value)
        Status.success
      rescue error : Tuya::Error | KeyError | IO::Error
        report_write_failure(failure_message(error))
        Status.failure
      ensure
        close_connection(client)
      end
    end

    private def close_connection(client : Tuya::Client?) : Nil
      client.try(&.close)
    rescue error : IO::Error
      Log.warn { "Closing Tuya switch #{switch_description} failed (#{error.class})" }
    end

    private def report(value : Bool) : Nil
      self.on_off = value
      @info.try(&.reachable=(true))
      @last_write_failure = nil
    end

    private def switch_description : String
      number = endpoint_id.number
      config = @config || return "on Matter endpoint #{number}"
      address = Socket::IPAddress.new(config.ip, config.port)
      "#{config.label.inspect} at #{address} (Matter endpoint #{number})"
    end

    private def failure_message(error : Exception) : String
      if error.is_a?(KeyError) && (config = @config)
        return "Status reply omitted power datapoint #{config.datapoint}"
      end

      cause = error.is_a?(Tuya::ConnectionError) ? error.cause : error
      if (io_error = cause.as?(IO::Error)) && (os_error = io_error.os_error)
        return os_error.message
      end
      cause.try(&.message) || error.message || error.class.name
    end

    private def report_write_failure(message : String) : Nil
      @info.try(&.reachable=(false))
      if message != @last_write_failure
        Log.warn { "Tuya switch #{switch_description} is unreachable. Power command failed. #{message}" }
        @last_write_failure = message
      end
    end
  end
end
