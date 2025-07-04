require "yaml"
require "./freeswitch/variant"

module Agent
  class FreeswitchStateConfig
    include YAML::Serializable

    property variant : String = "vanilla"

    def self.load(config_path = nil)
      if config_path.nil?
        FreeswitchStateConfig.from_yaml("---")
      else
        FreeswitchStateConfig.from_yaml(File.open(config_path))
      end
    end
  end

  class FreeswitchStateVariant
    def self.resolve(softswitch_id, variant) : SoftswitchState
      case variant
      when "fusionpbx"
        FreeswitchStateVariantFusionPBX.new(softswitch_id)
      else
        FreeswitchStateVariantVanilla.new(softswitch_id)
      end
    end
  end

  class FreeswitchState < SoftswitchState
    @variant : SoftswitchState

    def initialize(@softswitch_id : String, driver_config_path = nil)
      config = FreeswitchStateConfig.load(driver_config_path)
      @variant = FreeswitchStateVariant.resolve(@softswitch_id, config.variant)
    end

    def setup(config, driver_config_path = nil)
      @variant.setup(config, driver_config_path)
    end

    def software : String
      @variant.software
    end

    def version : String
      @variant.version
    end

    def bootstrap : Array(Agent::Event)
      @variant.not_nil!.bootstrap
    end

    def handle_action(action : Agent::Action) : Array(Agent::Event)
      @variant.not_nil!.handle_action(action)
    end

    def next_platform_events : Array(Agent::Event)
      @variant.not_nil!.next_platform_events
    end
  end
end
