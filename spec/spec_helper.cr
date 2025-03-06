require "spec"
require "../src/xdg"
require "file_utils"
require "system/user"
require "system/group"

module SpecHelpers

  def create_runtime_dir(path : String)
    user = System::User.find_by id: LibC.getuid.to_s
    parent = File.dirname(path)
    Dir.mkdir_p(parent) unless Dir.exists?(parent)

    Dir.mkdir(path)
    File.chmod(path, 0o700)
    pp! user
    pp! user.id
    pp! user.group_id
    # File.chown(path, uid: user.id, gid: user.group_id)
  end

  # Creates a temporary directory within spec/tmp and cleans up after
  def in_temp_dir(&)
    base_temp_dir = File.join("spec", "tmp")
    Dir.mkdir_p(base_temp_dir) unless Dir.exists?(base_temp_dir)

    temp_dir = File.join(base_temp_dir, Random::Secure.rand(8).to_s)
    Dir.mkdir(temp_dir)

    begin
      Dir.cd(temp_dir) { yield(temp_dir) }
    ensure
      FileUtils.rm_rf(temp_dir)
    end
  end

  def with_env(vars : Hash(String, String), &)
    tmp = {} of String => String
    vars.each do |k, v|
      tmp[k] = ENV[k]
    end

    vars.each do |k, v|
      ENV[k] = vars[k]
    end

    value = yield

    vars.each do |k, v|
      ENV[key] = tmp[k]
    end
    value
  end

  # Clears XDG-related environment variables temporarily
  def with_xdg_clean_env(&)
    tmp = {} of String => String
    keys = %w[XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME
      XDG_CONFIG_DIRS XDG_DATA_DIRS XDG_RUNTIME_DIR XDG_STRICT]
    keys.each do |k|
      tmp[k] = ENV[k]
    end

    keys.each do |k|
      ENV.delete(k)
    end

    yield

    keys.each do |k|
      if val = tmp[k]?
        ENV[k] = val
      end
    end
  end
end
