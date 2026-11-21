module TuyaMatter
  module CLI
    DEFAULT_CONFIG  = "config.yaml"
    DEFAULT_STORAGE = "data/tuya-matter.yml"

    HELP = <<-TEXT
      Usage: tuya-matter

      TUYA_CONFIG_FILE      Tuya device configuration (default: #{DEFAULT_CONFIG})
      MATTER_STORAGE_FILE   Persistent Matter state (default: #{DEFAULT_STORAGE})
      MATTER_PORT           Matter UDP port (default: #{Matter::Device::DEFAULT_PORT})
      LOG_LEVEL             Minimum log level (default: info)
      TEXT

    def self.run(args : Array(String) = ARGV) : Int32
      if args == ["--help"] || args == ["-h"]
        puts HELP
        return 0
      end
      raise ArgumentError.new("Use --help for configuration") unless args.empty?

      ::Log.setup("*", ::Log::Severity.parse(ENV["LOG_LEVEL"]? || "info"))
      config_path = ENV["TUYA_CONFIG_FILE"]? || DEFAULT_CONFIG
      config = Config.parse(File.read(config_path))
      storage_path = ENV["MATTER_STORAGE_FILE"]? || DEFAULT_STORAGE
      port = matter_port(ENV["MATTER_PORT"]?)
      Dir.mkdir_p(File.dirname(storage_path), mode: 0o700)
      storage = Matter::Storage::YamlFile.new(storage_path)
      bridge = Bridge.new(config, storage, port: port)

      stopping = Channel(Nil).new
      Process.on_terminate { stopping.close }
      bridge.start
      return 1 unless bridge.running?

      spawn do
        stopping.receive?
        bridge.shutdown!
      end
      bridge.await_shutdown
      0
    rescue error : ArgumentError | IO::Error | Matter::Error
      STDERR.puts "tuya-matter: #{error.message}"
      1
    ensure
      storage.try { |backend| backend.close if backend.open? }
    end

    private def self.matter_port(value : String?) : Int32
      return Matter::Device::DEFAULT_PORT unless value

      port = value.to_i?
      raise ArgumentError.new("MATTER_PORT must be an integer between 0 and 65535") unless port && (0..65_535).includes?(port)
      port
    end
  end
end
