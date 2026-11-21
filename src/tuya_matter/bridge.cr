module TuyaMatter
  class Bridge < Matter::Device
    AGGREGATOR_ENDPOINT = 1_u16
    DEFAULT_POLL        = 30.seconds

    private alias Info = Matter::Cluster::BridgedDeviceBasicInformation
    private record Identity, discriminator : UInt16, pin : UInt32, unique_id : String

    endpoint AGGREGATOR_ENDPOINT, device_type: Matter::DeviceType::AGGREGATOR

    endpoint_template :power_switch,
      device_type: [Matter::DeviceType::ON_OFF_PLUG_IN_UNIT, Matter::DeviceType::BRIDGED_NODE],
      parameters: {name: String, unique_id: String} do
      cluster PowerSwitch
      cluster Matter::Cluster::Identify
      cluster Matter::Cluster::Groups
      cluster Info, product_name: "Tuya Power Switch", node_label: name,
        unique_id: unique_id, reachable: false
    end

    @identity : Identity
    @switches = {} of PowerSwitch => SwitchConfig
    @stop_polling = Channel(Nil).new
    @poll_workers = [] of Channel(Nil)
    @shutdown_started = Atomic(Bool).new(false)

    def initialize(config : Config, storage : Matter::Storage::Backend,
                   *, port : Int32 = DEFAULT_PORT, ip_addresses : Array(Socket::IPAddress)? = nil,
                   @poll_interval : Time::Span = DEFAULT_POLL)
      storage.open
      @identity = load_identity(storage)
      super(storage, ip_addresses: ip_addresses, port: port)
      configure_switches(config.power_switches)
    end

    def device_name : String
      "Tuya Matter Bridge"
    end

    def primary_device_type_id : UInt32
      Matter::DeviceType::ROOT_NODE
    end

    def vendor_id : UInt16
      Matter::SetupPayload::TEST_VENDOR_ID_MINIMUM
    end

    def product_id : UInt16
      0xE002_u16
    end

    def discriminator : UInt16
      @identity.discriminator
    end

    def setup_pin : UInt32
      @identity.pin
    end

    def unique_id : String
      @identity.unique_id
    end

    def running? : Bool
      @started
    end

    def shutdown! : Nil
      return if @shutdown_started.swap(true)

      begin
        @stop_polling.close
        @poll_workers.each(&.receive?)
        @switches.each_key(&.disconnect)
      ensure
        super
      end
    end

    protected def started_commissioning_mode : Nil
      payload = Matter::SetupPayload::QRCode.generate_qr_code(discriminator, setup_pin, vendor_id, product_id,
        capabilities: Matter::SetupPayload::QRCode::DiscoveryCapability::OnNetwork)
      puts "Matter QR payload: #{payload}"
      puts "Matter manual pairing code: #{Matter::SetupPayload.generate_manual_code(discriminator, setup_pin)}"
      STDOUT.flush
    end

    protected def on_started : Nil
      versions = {} of Tuple(String, String) => Tuya::Version
      discovery_done = discover_versions(versions) if @switches.values.any?(&.version.nil?)

      @switches.each do |switch, config|
        done = Channel(Nil).new
        @poll_workers << done
        spawn do
          discovery_done.try(&.receive?) if config.version.nil?
          poll(switch, versions[{config.device_id, config.ip}]?)
        ensure
          done.close
        end
      end
    end

    private def discover_versions(versions : Hash(Tuple(String, String), Tuya::Version)) : Channel(Nil)
      done = Channel(Nil).new
      @poll_workers << done
      spawn do
        Tuya::Discovery.scan(2.seconds).each do |device|
          versions[{device.id, device.ip}] = device.version
        end
      rescue error : Tuya::Error
        Log.debug { "Tuya discovery unavailable (#{error.message})" }
      ensure
        done.close
      end
      done
    end

    private def poll(switch : PowerSwitch, announced_version : Tuya::Version?) : Nil
      until @stop_polling.closed?
        switch.refresh(announced_version)
        select
        when @stop_polling.receive?
          break
        when timeout(@poll_interval)
        end
      end
    end

    # The library restores endpoint templates from storage. Rebind them by
    # device identity so edits to the order of the config keep endpoint IDs.
    private def configure_switches(configs : Array(SwitchConfig)) : Nil
      configured = configs.to_h { |entry| {entry.unique_id, entry} }
      endpoint_ids.each do |id|
        endpoint = node.endpoint!(id)
        next unless info = endpoint.get_cluster(Info)

        if entry = configured.delete(info.unique_id)
          bind_switch(endpoint, info, entry)
        else
          remove_endpoint(id, notify_subscribers: false)
        end
      end

      configured.each_value do |entry|
        endpoint = add_endpoint(:power_switch, parent_endpoint: AGGREGATOR_ENDPOINT,
          name: entry.label, unique_id: entry.unique_id)
        bind_switch(endpoint, endpoint.get_cluster!(Info), entry)
      end
    end

    private def bind_switch(endpoint : Matter::Endpoint, info : Info, entry : SwitchConfig) : Nil
      info.node_label = entry.label
      switch = endpoint.get_cluster!(PowerSwitch)
      switch.attach(entry, info)
      @switches[switch] = entry
    end

    private def load_identity(storage : Matter::Storage::Backend) : Identity
      if record = storage.read("tuya_matter", "identity")
        return Identity.new(record["discriminator"].as(Int64).to_u16, record["pin"].as(Int64).to_u32,
          record["unique_id"].as(String))
      end

      identity = Identity.new(Matter::SetupPayload.generate_random_discriminator,
        Matter::SetupPayload.generate_random_pin, Matter::SetupPayload.generate_unique_id)
      storage.write("tuya_matter", "identity", Matter::Storage::Document{
        "discriminator" => identity.discriminator.to_i64, "pin" => identity.pin.to_i64,
        "unique_id" => identity.unique_id,
      })
      identity
    end
  end
end
