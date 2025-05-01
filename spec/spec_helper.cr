require "log"
require "spec"
require "../src/xdg"
require "file_utils"
require "system/user"
require "system/group"

Log.setup_from_env


# Helper for creating valid runtime directories
def create_runtime_dir(path)
  # Ensure parent exists if needed
  parent = Path[path].parent
  Dir.mkdir_p(parent.to_s) unless Dir.exists?(parent.to_s)

  # Create with 0700
  Dir.mkdir(path, 0o700)
  File.chmod(path, 0o700) # <-- Add explicit permission set

  # Removed chown attempt as tests no longer rely on specific ownership
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

# In spec/spec_helper.cr - Improve in_temp_dir helper
def in_temp_dir(&)
  # Create temp dir under system temp dir with random name
  parent_dir = Path[Dir.tempdir] / "xdg_spec"
  Dir.mkdir(parent_dir.to_s) unless Dir.exists?(parent_dir.to_s)

  test_dir = parent_dir / Random::Secure.hex(8)
  Dir.mkdir(test_dir.to_s)

  begin
    FileUtils.cd(test_dir) do
      yield test_dir
    end
  ensure
    # Force-cleanup even if permissions get messed up
    FileUtils.rm_rf(test_dir.to_s) if Dir.exists?(test_dir.to_s)
  end
end
