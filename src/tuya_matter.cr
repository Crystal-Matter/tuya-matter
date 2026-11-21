require "log"
require "yaml"
require "digest/sha256"
require "matter"
require "tuya_client"

require "./tuya_matter/config"
require "./tuya_matter/power_switch"
require "./tuya_matter/bridge"

module TuyaMatter
  Log = ::Log.for(self)
end
