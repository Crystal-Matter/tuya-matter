require "spec"
require "../src/tuya_matter"

describe TuyaMatter::Config do
  it "defaults to automatic protocol detection and accepts an override" do
    config = TuyaMatter::Config.parse(<<-YAML)
      power_switch: [
        {"ip": "192.0.2.1", "device_id": "first", "key": "0123456789abcdef"},
        {"ip": "192.0.2.2", "device_id": "second", "key": "0123456789abcdef",
         "version": 3.5, "datapoint": 7, "name": "Desk"}
      ]
      YAML
    config.power_switches.size.should eq(2)
    config.power_switches[0].version_override.should be_nil
    config.power_switches[1].version_override.should eq(Tuya::Version::V35)
    config.power_switches[1].client(Tuya::Version::V35).on_datapoint.should eq("7")
    config.power_switches[1].label.should eq("Desk")
  end

  it "rejects duplicate identities" do
    expect_raises(ArgumentError, /already configured/) do
      TuyaMatter::Config.parse(<<-YAML)
        power_switch:
          - {ip: "192.0.2.1", device_id: "first", key: "0123456789abcdef"}
          - {ip: "192.0.2.2", device_id: "first", key: "0123456789abcdef"}
        YAML
    end
  end

  it "identifies invalid keys without exposing their value" do
    expect_raises(ArgumentError, "power_switch[0].key must be 16 bytes") do
      TuyaMatter::Config.parse(<<-YAML)
        power_switch:
          - {ip: "192.0.2.1", device_id: "first", key: "incorrect"}
        YAML
    end
  end
end
