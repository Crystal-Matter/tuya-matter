module TuyaMatter
  class SwitchConfig
    include YAML::Serializable
    include YAML::Serializable::Strict

    getter ip : String
    getter device_id : String
    getter name : String?
    getter version : String?
    getter port : Int32 = Tuya::Client::DEFAULT_PORT
    getter datapoint : Int32 = 1
    getter? assume_off_when_missing : Bool = false
    getter query_datapoints : Array(Int32)?

    @key : String

    def version_override : Tuya::Version?
      @version.try { |version| Tuya::Version.parse(version) }
    end

    def client(version : Tuya::Version, *, timeout : Time::Span = 5.seconds) : Tuya::Client
      query = @query_datapoints || ([1, @datapoint].uniq if version.v32?)
      Tuya::Client.new(@ip, @device_id, @key, version: version, port: @port, timeout: timeout,
        on_datapoint: @datapoint, query_datapoints: query)
    end

    def label : String
      @name || "Tuya Switch #{unique_id[0, 6]}"
    end

    def unique_id : String
      Digest::SHA256.hexdigest(@device_id)[0, 32]
    end

    def validate(index : Int32) : Nil
      path = "power_switch[#{index}]"
      raise ArgumentError.new("#{path}.ip must be an IP address") unless Socket::IPAddress.valid?(@ip)
      raise ArgumentError.new("#{path}.device_id must be nonempty") if @device_id.strip.empty?
      raise ArgumentError.new("#{path}.key must be 16 bytes") unless @key.bytesize == 16
      raise ArgumentError.new("#{path}.port must be between 1 and 65535") unless (1..65_535).includes?(@port)
      raise ArgumentError.new("#{path}.datapoint must be between 1 and 255") unless (1..255).includes?(@datapoint)
      if (name = @name) && (name.strip.empty? || name.bytesize > 32)
        raise ArgumentError.new("#{path}.name must be nonempty and at most 32 bytes")
      end

      validate_version(path)
      if (ids = @query_datapoints) && (!ids.includes?(@datapoint) || ids.any? { |id| !(1..255).includes?(id) })
        raise ArgumentError.new("#{path}.query_datapoints must contain the switch datapoint and only IDs between 1 and 255")
      end
    end

    private def validate_version(path : String) : Nil
      version_override
    rescue ArgumentError
      raise ArgumentError.new("#{path}.version must be between 3.1 and 3.5")
    end
  end

  class Config
    include YAML::Serializable
    include YAML::Serializable::Strict

    @[YAML::Field(key: "power_switch")]
    getter power_switches = [] of SwitchConfig

    def self.parse(yaml : String) : self
      config = from_yaml(yaml)
      device_ids = Set(String).new
      config.power_switches.each_with_index do |switch_config, index|
        switch_config.validate(index)
        unless device_ids.add?(switch_config.device_id)
          raise ArgumentError.new("power_switch[#{index}].device_id is already configured")
        end
      end
      config
    rescue error : YAML::ParseException
      raise ArgumentError.new("Invalid YAML configuration at line #{error.line_number}, column #{error.column_number}")
    end
  end
end
