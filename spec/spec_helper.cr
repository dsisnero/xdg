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

  # Helper for creating valid runtime directories
  def create_runtime_dir(path)
    # Ensure parent exists if needed
    parent = Path[path].parent
    Dir.mkdir_p(parent.to_s) unless Dir.exists?(parent.to_s)

    # Create with 0700
    Dir.mkdir(path, 0o700)
    File.chmod(path, 0o700) # <-- Add explicit permission set

    # Set owner to current user - crucial for validation
    # Note: File.chown changes GROUP first, then USER. Use nil for group if only changing user.
    # On some systems, chown might require root privileges.
    begin
      # Use keyword arguments for clarity if supported, otherwise positional
      # Assuming File.chown(path, uid, gid) signature
      File.chown(path, Process.uid.to_i, -1) # Use -1 to keep group
    rescue ex : File::Error # Changed from Errno to File::Error
      # Log if chown fails, test might still pass if user already owns it,
      # but validation could fail otherwise.
      puts "Warning: Failed to chown #{path} to UID #{Process.uid}: #{ex.message}. Test validity may depend on initial ownership."
    rescue ex : ArgumentError
      # Crystal's File.chown uses positional arguments, not keywords.
      # Just log the argument error.
      puts "Warning: Invalid arguments for chown on #{path}: #{ex.message}"
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

  def in_temp_dir(&)
    tempdir = File.join(Dir.tempdir, "xdg_spec_#{Random::Secure.hex(8)}")
    Dir.mkdir(tempdir)

    begin
      File.chdir(tempdir) do
        yield Path.new(tempdir)
      end
    ensure
      FileUtils.rm_rf(tempdir) if Dir.exists?(tempdir)
    end
  end

end
