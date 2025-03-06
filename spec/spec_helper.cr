require "spec"
require "../src/xdg"
require "file_utils"
require "system/user"
require "system/group"

class Process

  def self.uid
    LibC.getuid.to_s
  end

end

module SpecHelpers

  def create_runtime_dir(path : String)
    user = System::User.find_by(id: Process.uid)
    raise "User #{Process.uid} not found" unless user
    
    parent = File.dirname(path)
    Dir.mkdir_p(parent) unless Dir.exists?(parent)

    Dir.mkdir_p(path)
    File.chmod(path, 0o700)
    File.chown(path, uid: user.id.to_i, gid: user.group_id.to_i)
  end

  # Creates a temporary directory within spec/tmp and cleans up after
  def in_temp_dir(&)
    base_temp_dir = File.join("spec", "tmp")
    Dir.mkdir_p(base_temp_dir) unless Dir.exists?(base_temp_dir)
    
    temp_dir = File.join(base_temp_dir, Random::Secure.hex(8))
    Dir.mkdir_p(temp_dir)
    
    begin
      Dir.cd(temp_dir) { yield(temp_dir) }
    ensure
      FileUtils.rm_rf(temp_dir)
    end
  end

  def with_env(vars : Hash(String, String), &)
    original = {} of String => String?
    vars.each_key do |k|
      original[k] = ENV[k]?
      ENV[k] = vars[k]
    end

    yield
  ensure
    vars.each_key do |k|
      if original[k]?
        ENV[k] = original[k].not_nil!
      else
        ENV.delete(k)
      end
    end
  end

 def with_xdg_clean_env(&)
   # Explicit type declaration
   original = Hash(String, String?).new

   {% for var in %w[XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME
                   XDG_CONFIG_DIRS XDG_DATA_DIRS XDG_RUNTIME_DIR XDG_STRICT] %}
     original[{{var}}] = ENV[{{var}}]?
     ENV.delete({{var}})
   {% end %}

   yield
 ensure
   {% for var in %w[XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME
                   XDG_CONFIG_DIRS XDG_DATA_DIRS XDG_RUNTIME_DIR XDG_STRICT] %}
     # Changed from original[{{var}}]? to original.has_key?({{var}})
     if original.not_nil!.has_key?({{var}})
       value = original.not_nil![{{var}}]
       if value
         ENV[{{var}}] = value
       else
         ENV.delete({{var}})
       end
     end
   {% end %}

 end
  

end
