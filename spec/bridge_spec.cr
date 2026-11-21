require "spec"
require "log/spec"
require "../src/tuya_matter"
require "./support/tuya_fixture"

private alias Info = Matter::Cluster::BridgedDeviceBasicInformation
private alias Status = Matter::InteractionModel::Status

private def switch_entry(id : String, port : Int32, name : String = id) : NamedTuple
  {ip: "127.0.0.1", device_id: id, key: TuyaFixture::KEY, port: port, name: name}
end

private def config_for(*switches) : TuyaMatter::Config
  TuyaMatter::Config.parse({power_switch: switches.to_a}.to_json)
end

private def bridge_for(config : TuyaMatter::Config, storage : Matter::Storage::Backend = Matter::Storage::Memory.new) : TuyaMatter::Bridge
  TuyaMatter::Bridge.new(config, storage, port: 0, ip_addresses: [Socket::IPAddress.new("127.0.0.1", 0)])
end

describe TuyaMatter::Bridge do
  it "detects the switch protocol before forwarding Matter commands to Tuya" do
    first = TuyaFixture.new
    second = TuyaFixture.new
    bridge = bridge_for(config_for(switch_entry("First", first.port), switch_entry("Second", second.port)))
    aggregator = bridge.node.endpoint!(1_u16)
    aggregator.device_types.map(&.device_type_id.id).should eq([Matter::DeviceType::AGGREGATOR])
    aggregator.descriptor.parts_list.should eq([2_u16, 3_u16])
    endpoint = bridge.node.endpoint!(2_u16)
    endpoint.parent_endpoint_id.should eq(1_u16)
    endpoint.device_types.map(&.device_type_id.id).should eq([
      Matter::DeviceType::ON_OFF_PLUG_IN_UNIT, Matter::DeviceType::BRIDGED_NODE,
    ])

    info = endpoint.get_cluster!(Info)
    cluster = endpoint.get_cluster!(TuyaMatter::PowerSwitch)
    info.reachable?.should be_false
    cluster.refresh
    info.reachable?.should be_true
    cluster.on_off?.should be_false
    first.writes.should be_empty

    cluster.invoke_command(1_u32).should eq(Status.success)
    first.on?.should be_true
    second.on?.should be_false

    cluster.invoke_command(0_u32).should eq(Status.success)
    first.on?.should be_false

    first.on = true
    cluster.invoke_command(2_u32).should eq(Status.success)
    first.on?.should be_false
    first.writes.should eq([true, false, false])

    first.on = true
    cluster.refresh
    cluster.on_off?.should be_true
    first.writes.size.should eq(3)

    first.reject_commands = true
    cluster.invoke_command(0_u32).should eq(Status.failure)
    cluster.on_off?.should be_true
    info.reachable?.should be_true

    first.close
    cluster.refresh
    info.reachable?.should be_false
    other_switch = bridge.node.endpoint!(3_u16).get_cluster!(TuyaMatter::PowerSwitch)
    other_switch.refresh
    other_switch.invoke_command(1_u32).should eq(Status.success)
    second.on?.should be_true
  ensure
    bridge.try &.shutdown!
    first.try &.close
    second.try &.close
  end

  it "identifies the endpoint and the socket error when a device resets connections" do
    fixture = TuyaFixture.new(reset_connections: true)

    Log.capture("tuya_matter") do |logs|
      bridge = bridge_for(config_for(switch_entry("first", 6668), switch_entry("second", fixture.port, "Upstairs Kettle")))
      endpoint = bridge.node.endpoint!(3_u16)
      endpoint.get_cluster!(TuyaMatter::PowerSwitch).refresh
      endpoint.get_cluster!(Info).reachable?.should be_false

      logs.check(:info, /Configured Tuya switch "Upstairs Kettle" at 127\.0\.0\.1:\d+ \(Matter endpoint 3\)/)
      logs.check(:warn, /"Upstairs Kettle" at 127\.0\.0\.1:\d+ \(Matter endpoint 3\) is unreachable\. Status probes failed/)
      logs.entry.message.should contain("Connection reset by peer")
      logs.entry.message.should contain("3.5")
      logs.entry.message.should contain("3.1")
      logs.entry.message.should_not contain("#<TCPSocket:")
    ensure
      bridge.try &.shutdown!
    end
  ensure
    fixture.try &.close
  end

  it "persists commissioning identity and endpoint numbers across config edits" do
    storage = Matter::Storage::Memory.new
    first = switch_entry("First", 6668)
    second = switch_entry("Second", 6668)
    initial = bridge_for(config_for(first, second), storage)
    pin = initial.setup_pin
    discriminator = initial.discriminator
    unique_id = initial.unique_id
    second_id = initial.node.endpoint!(3_u16).get_cluster!(Info).unique_id
    initial.shutdown!

    reordered = bridge_for(config_for(switch_entry("Second", 6668, "Renamed"), first), storage)
    reordered.setup_pin.should eq(pin)
    reordered.discriminator.should eq(discriminator)
    reordered.unique_id.should eq(unique_id)
    info = reordered.node.endpoint!(3_u16).get_cluster!(Info)
    info.unique_id.should eq(second_id)
    info.node_label.should eq("Renamed")
    reordered.shutdown!

    updated = bridge_for(config_for(second), storage)
    updated.endpoint_ids.should eq([1_u16, 3_u16])
    updated.node.endpoint!(3_u16).get_cluster!(Info).unique_id.should eq(second_id)
  ensure
    initial.try &.shutdown!
    reordered.try &.shutdown!
    updated.try &.shutdown!
  end
end
