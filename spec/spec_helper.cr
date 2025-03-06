require "spec"
require "../src/xdg"
require "file_utils"
require "secure_random"

module SpecHelpers
  # Creates a temporary directory within spec/tmp and cleans up after
  def in_temp_dir
    base_temp_dir = File.join("spec", "tmp")
    Dir.mkdir_p(base_temp_dir) unless Dir.exists?(base_temp_dir)
    
    temp_dir = File.join(base_temp_dir, SecureRandom.hex(8))
    Dir.mkdir(temp_dir)
    
    begin
      Dir.cd(temp_dir) { yield(temp_dir) }
    ensure
      FileUtils.rm_rf(temp_dir)
    end
  end

  # Clears XDG-related environment variables temporarily
  def with_xdg_clean_env
    original = {} of String => String?
    {% for var in %w[XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME
                     XDG_CONFIG_DIRS XDG_DATA_DIRS XDG_RUNTIME_DIR XDG_STRICT] %}
      original[{{var}}] = ENV[{{var}}]?
      ENV.delete({{var}})
    {% end %}
    
    yield
  ensure
    {% for var in %w[XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME
                     XDG_CONFIG_DIRS XDG_DATA_DIRS XDG_RUNTIME_DIR XDG_STRICT] %}
      ENV[{{var}}] = original[{{var}}]?.try(&.to_s)
    {% end %}
  end
end

include SpecHelpers
