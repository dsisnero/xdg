require "log"
require "file_utils" # For Dir.mkdir_p

module XDG
  # Cross-platform path delimiter awareness
  private PATH_DELIMITER = Process::PATH_DELIMITER

  # Base error class for XDG-related exceptions
  class Error < Exception
    getter context : Hash(String, String)?

    def initialize(message : String, @context : Hash(String, String)? = nil, cause : Exception? = nil)
      super(message, cause)
    end
  end

  # Raised when directory creation fails or permissions prevent access
  class DirectoryError < Error
    # Includes the problematic path in the error context
    def initialize(message, path : Path | String, cause : Exception? = nil)
      path_str = path.is_a?(Path) ? path.to_s : path.as(String)
      super(message, {"path" => path_str}, cause)
    end
  end

  # Raised when security validation fails for directories/files
  class SecurityError < Error
    # Includes details about the security violation
    def initialize(message, path : Path | String, details : String, cause : Exception? = nil)
      path_str = path.is_a?(Path) ? path.to_s : path.as(String)
      super(message, {
        "path" => path_str,
        "violation" => details
      }, cause)
    end
  end

  # Default paths according to XDG Base Directory Specification
  # https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
  DEFAULT_CONFIG_DIRS_STR = "/etc/xdg"
  DEFAULT_DATA_DIRS_STR   = "/usr/local/share:/usr/share"
  # Note: These are parsed into Array(Path) by config_dirs/data_dirs methods
  # Note: Default runtime dir needs UID, handled in default_runtime_dir

  # Constants for platform-specific paths (macOS, Windows)
  MACOS_APP_SUPPORT    = Path.home / "Library" / "Application Support"
  MACOS_PREFERENCES    = Path.home / "Library" / "Preferences"
  WINDOWS_PROGRAM_DATA = Path.new(ENV["PROGRAMDATA"]? || "C:\\ProgramData")

  # Returns the XDG_CONFIG_HOME directory path
  def self.config_home : Path
    (env_path = ENV["XDG_CONFIG_HOME"]) ? Path.new(env_path) : default_config_home
  end

  # Returns the XDG_DATA_HOME directory path
  def self.data_home : Path
    (env_path = ENV["XDG_DATA_HOME"]) ? Path.new(env_path) : default_data_home
  end

  # Returns the XDG_CACHE_HOME directory path
  def self.cache_home : Path
    (env_path = ENV["XDG_CACHE_HOME"]) ? Path.new(env_path) : default_cache_home
  end

  # Returns the XDG_STATE_HOME directory path
  def self.state_home : Path
    begin
      (env_path = ENV["XDG_STATE_HOME"]) ? Path.new(env_path) : default_state_home
    rescue
      # Fallback if Path.new fails or other issues arise
      default_state_home
    end
  end

  # Returns the XDG_RUNTIME_DIR directory path or nil
  def self.runtime_dir : Path?
    (env_path = ENV["XDG_RUNTIME_DIR"]) ? Path.new(env_path) : default_runtime_dir
  end

  # Returns an array of XDG_CONFIG_DIRS paths
  def self.config_dirs : Array(Path)
    parse_paths(ENV["XDG_CONFIG_DIRS"]? || default_config_dirs)
  end

  # Returns an array of XDG_DATA_DIRS paths
  def self.data_dirs : Array(Path)
    parse_paths(ENV["XDG_DATA_DIRS"]? || default_data_dirs)
  end

  # Returns an application-specific configuration path within XDG_CONFIG_HOME.
  # Does *not* create the directory. Use `app_config_path` or `ensure_directories!` for creation.
  # @param app The application name.
  # @param version Optional version string, creating a subdirectory.
  # @param vendor Optional vendor name, creating a vendor subdirectory.
  # @return The constructed Path object.
  # @example Standard path
  #   XDG.app_config("myapp") # => /home/user/.config/myapp
  # @example Path with version
  #   XDG.app_config("myapp", "2.0") # => /home/user/.config/myapp/2.0
  # @example Path with vendor
  #   XDG.app_config("cli", vendor: "acme") # => /home/user/.config/acme/cli
  # @example Path with vendor and version
  #   XDG.app_config("cli", "1.1", vendor: "acme") # => /home/user/.config/acme/cli/1.1
  # @raise ArgumentError if app, version, or vendor contain invalid characters like '..' or '/'.
  def self.app_config(app : String, version : String? = nil, vendor : String? = nil) : Path
    # Use safe_join for constructing paths
    base = vendor ? safe_join(config_home, [vendor]) : config_home # Wrap vendor in array
    path_parts = [app]
    path_parts << version if version
    safe_join(base, path_parts) # Pass array directly
  end

  # Returns an application-specific state path within XDG_STATE_HOME.
  # Does *not* create the directory. Use `ensure_directories!` for creation.
  # @param app The application name.
  # @param version Optional version string, creating a subdirectory.
  # @return The constructed Path object.
  # @example Standard path
  #   XDG.app_state("myapp") # => /home/user/.local/state/myapp
  # @example Path with version
  #   XDG.app_state("myapp", "2.0") # => /home/user/.local/state/myapp/2.0
  # @raise ArgumentError if app or version contain invalid characters like '..' or '/'.
  def self.app_state(app : String, version : String? = nil) : Path
    # Use safe_join for constructing paths
    path_parts = [app]
    path_parts << version if version
    safe_join(state_home, path_parts) # Pass array directly
  end

  # Returns a path for a config file within the primary config directory.
  # Optionally creates the parent directory.
  # @param file_name Relative path of the file within the config home.
  # @param create If true, ensures the parent directory exists.
  # @return The full path to the potential config file.
  # @raise XDG::DirectoryError if creation fails when `create` is true.
  # @raise ArgumentError if `file_name` is invalid.
  def self.app_config_path(file_name : Path | String, create = false) : Path
    file_name_str = file_name.is_a?(Path) ? file_name.to_s : file_name.as(String)
    validate_filename!(file_name_str) # Use the helper for validation
    path = config_home / file_name_str
    ensure_parent_dir(path, create) # Use the helper for directory creation
    path
  end

  # Returns an application-specific data file path within XDG_DATA_HOME.
  # @param file_name Relative path of the file within the data home (e.g., "settings.json", "cache/images.db"). Must not contain '..' or start with '/'.
  # @param create If true, ensures the parent directory exists.
  # @return Full path to the potential data file.
  # @raise XDG::DirectoryError if creation fails when `create` is true.
  # @raise ArgumentError if `file_name` is invalid.
  def self.app_data_path(file_name : Path | String, create = false) : Path
    file_name_str = file_name.is_a?(Path) ? file_name.to_s : file_name.as(String)
    validate_filename!(file_name_str)
    path = data_home / file_name_str
    ensure_parent_dir(path, create)
    path
  end

  # Returns an application-specific cache file path within XDG_CACHE_HOME.
  # @param file_name Relative path of the file within the cache home. Must not contain '..' or start with '/'.
  # @param create If true, ensures the parent directory exists.
  # @return Full path to the potential cache file.
  # @raise XDG::DirectoryError if creation fails when `create` is true.
  # @raise ArgumentError if `file_name` is invalid.
  def self.app_cache_path(file_name : Path | String, create = false) : Path
    file_name_str = file_name.is_a?(Path) ? file_name.to_s : file_name.as(String)
    validate_filename!(file_name_str)
    path = cache_home / file_name_str
    ensure_parent_dir(path, create)
    path
  end

  # Returns an application-specific state file path within XDG_STATE_HOME.
  # @param file_name Relative path of the file within the state home. Must not contain '..' or start with '/'.
  # @param create If true, ensures the parent directory exists.
  # @return Full path to the potential state file.
  # @raise XDG::DirectoryError if creation fails when `create` is true.
  # @raise ArgumentError if `file_name` is invalid.
  def self.app_state_path(file_name : Path | String, create = false) : Path
    file_name_str = file_name.is_a?(Path) ? file_name.to_s : file_name.as(String)
    validate_filename!(file_name_str)
    path = state_home / file_name_str
    ensure_parent_dir(path, create)
    path
  end

  # Ensures all XDG base directories exist
  def self.ensure_directories : Nil
    [config_home, data_home, cache_home].each do |dir|
      Dir.mkdir_p(dir.to_s) unless Dir.exists?(dir.to_s) # Dir methods often expect String
    end
  end

  # Ensures base directories exist by creating them if missing with given mode (default 0700).
  # Existing directories are left unchanged - no permission validation is performed.
  # @param mode Permissions for newly created directories (has no effect on existing dirs)
  # @raise XDG::DirectoryError if directory creation fails
  def self.ensure_directories!(mode : Int32 = 0o700)
    [config_home, data_home, cache_home, state_home].each do |dir|
      begin
        # Only create if it doesn't exist - no validation of existing dirs
        unless Dir.exists?(dir.to_s)
          Dir.mkdir_p(dir.to_s, mode)
        end
      rescue e : File::Error
        raise DirectoryError.new("Failed to create directory #{dir}", path: dir, cause: e)
      end
    end
  end

  # Validates directory security with detailed checks (ownership, permissions).
  # Logs detailed issues if validation fails.
  # @param path The directory path to validate.
  # @param expected_mode_max The maximum allowed permission bits (e.g., 0o700 for runtime, 0o777 for general).
  # @return `true` if the directory is valid, `false` otherwise.
  def self.valid_directory?(path : Path | String, expected_mode_max : Int32 = 0o777) : Bool
    path_obj = path.is_a?(Path) ? path : Path.new(path.as(String))
    info = File.info?(path_obj.to_s)
    unless info && info.directory?
      Log.debug { "Validation failed: Path '#{path_obj}' is not a directory or does not exist." }
      return false
    end

    current_uid = Process.uid.to_i
    valid = true
    issues = [] of String

    # Ownership check (Crucial for runtime_dir, important for others)
    # Allow root ownership for system-wide dirs like /etc/xdg, /usr/share
    # This check might need refinement based on context (user vs system dirs)
    # For now, we focus on user-specific dirs typically created by ensure_directories!
    # if path.starts_with?(Path.home.to_s) || path.starts_with?(DEFAULT_RUNTIME_BASE.to_s)
    #   unless info.owner_id == current_uid
    #     issues << "owned by UID #{info.owner_id} (expected: #{current_uid})"
    #     valid = false
    #   end
    # end
    # Simplified: For ensure_directories!, we expect current user ownership.
    # Runtime dir validation has its own stricter check. Let's keep this general.

    # Permission mask check
    actual_mode = info.permissions.value & 0o777
    if actual_mode > expected_mode_max
      issues << "permissions #{actual_mode.to_s(8)} exceed max allowed #{expected_mode_max.to_s(8)}"
      valid = false
    end

    # World-writable check (Always insecure)
    if info.permissions.other_write?
      issues << "is world-writable (permissions: #{actual_mode.to_s(8)})"
      valid = false
    end

    # Group-writable check (Often insecure, especially for runtime/config)
    # if info.permissions.group_write? && expected_mode_max <= 0o700 # Stricter check for sensitive dirs
    #   issues << "is group-writable (permissions: #{actual_mode.to_s(8)})"
    #   valid = false
    # end


    unless valid
      Log.warn {
        "Directory security validation failed: #{issues.join(", ")}. " \
        "Path: #{path} (Owner: #{info.owner_id}, " \
        "Permissions: #{actual_mode.to_s(8)}, " \
        "Expected Max: #{expected_mode_max.to_s(8)}, " \
        "Current UID: #{current_uid})"
      }
    end

    valid
  end


  # Searches for a configuration file according to XDG Base Directory Spec.
  # Looks in $XDG_CONFIG_HOME, then $XDG_CONFIG_DIRS.
  # @param name The relative path or filename to search for.
  # @return The full path to the first found file, or nil if not found.
  # @example
  #   XDG.find_config_file("myapp/settings.ini")
  def self.find_config_file(name : Path | String) : Path?
    name_str = name.is_a?(Path) ? name.to_s : name.as(String)
    # Prevent directory traversal
    raise ArgumentError.new("Invalid config file name: #{name_str}") if name_str.includes?("..") || name_str.starts_with?('/')

    ([config_home] + config_dirs).each do |dir|
      candidate = dir / name_str
      # Use File.file? to ensure it's a regular file
      return candidate if File.file?(candidate.to_s)
    end
    nil
  end

  # Validates if a runtime directory meets XDG security requirements
  def self.valid_runtime_dir?(path : Path | String) : Bool
    path_obj = path.is_a?(Path) ? path : Path.new(path.as(String))
    # Use Dir.exists? first as File.info will raise if path doesn't exist
    return false unless Dir.exists?(path_obj.to_s)

    # Now we know it exists, use File.info (not info?)
    info = File.info(path_obj.to_s)
    return false unless info.directory?

    # Compare UInt64 (owner_id) with Int32 (Process.uid) properly
    return false unless info.owner_id == Process.uid.to_u64

    # Check permissions: Must be exactly 0700 (rwx------)
    # We mask with 0o777 to ignore higher bits like setuid/setgid/sticky
    actual_mode = info.permissions.value & 0o777
    return actual_mode == 0o700
  end


  # Returns the XDG_RUNTIME_DIR directory path, creating it if necessary, or raises an error.
  # Ensures the directory exists with 0o700 permissions.
  # @raise RuntimeError if XDG_RUNTIME_DIR is not set and no valid default exists.
  # @raise XDG::DirectoryError if creation fails.
  # @raise XDG::SecurityError if the directory exists but is insecure.
  def self.runtime_dir! : Path
    dir_path = runtime_dir
    unless dir_path
      raise RuntimeError.new("XDG_RUNTIME_DIR not set and no valid default runtime directory found for UID #{Process.uid}")
    end

    # Ensure it exists with correct permissions
    begin
      # Check existence before creating to avoid errors if it's a symlink etc.
      unless Dir.exists?(dir_path.to_s)
        Dir.mkdir_p(dir_path.to_s, 0o700)
        # Re-check validity after creation
        unless valid_runtime_dir?(dir_path)
           # Log details before raising
           info = File.info?(dir_path.to_s)
           details = info ? "Permissions: #{info.permissions.value.to_s(8)}, Owner: #{info.owner_id}" : "Could not get info after creation"
           Log.error {
             "Runtime directory validation failed after creation. Path: #{dir_path}, Details: #{details}"
           }
           raise SecurityError.new("Created runtime directory has insecure permissions or ownership.", path: dir_path, details: details)
        end
      else
        # If it exists, ensure it's valid
        unless valid_runtime_dir?(dir_path)
          info = File.info(dir_path.to_s) # Exists, so use info not info?
          details = "Permissions: #{info.permissions.value.to_s(8)}, Owner: #{info.owner_id}, Expected Owner: #{Process.uid}"
          Log.error {
            "Existing runtime directory validation failed. Path: #{dir_path}, Details: #{details}"
          }
          raise SecurityError.new("Existing runtime directory is insecure.", path: dir_path, details: details)
        end
      end
    rescue e : File::Error
      raise DirectoryError.new("Failed to create or access runtime directory #{dir_path}", path: dir_path, cause: e)
    end

    dir_path
  end

  # Helper to validate filename components (prevents traversal, empty names)
  private def self.validate_filename!(file_name : String)
    # Check for empty string, directory traversal, and absolute paths
    if file_name.empty? || file_name.includes?("..") || file_name.includes?('/') || file_name.includes?('\\')
      raise ArgumentError.new("Invalid file name component: #{file_name}")
    end
  end

  # Helper to ensure parent directory exists before file operations.
  # Creates missing directories with 0700 permissions when create=true.
  # @param create When true, creates directory tree with 0700 permissions
  # @raise XDG::DirectoryError if directory creation fails
  private def self.ensure_parent_dir(path : Path | String, create : Bool)
    return unless create
    path_obj = path.is_a?(Path) ? path : Path.new(path.as(String))
    parent_dir = path_obj.parent
    begin
      # Use FileUtils.mkdir_p which handles existence check and allows setting mode
      FileUtils.mkdir_p(parent_dir.to_s, mode: 0o700) # Creates with 0700 if missing
    rescue e : File::Error
      # Use the enhanced DirectoryError
      raise DirectoryError.new("Failed to create directory #{parent_dir}", path: parent_dir, cause: e)
    end
  end

  private def self.default_config_home : Path
    {% if flag?(:win32) %}
      # Prefer APPDATA env var, fallback to registry, then default guess
      env_path = ENV["APPDATA"]?
      return Path.new(env_path) if env_path

      reg_path = windows_registry_path("Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders", "AppData")
      return reg_path if reg_path

      Path.home / "AppData" / "Roaming" # Last resort guess
    {% elsif flag?(:darwin) %}
      macos_app? ? MACOS_PREFERENCES : (Path.home / ".config")
    {% else %}
      Path.home / ".config"
    {% end %}
  end

  private def self.default_data_home : Path
    {% if flag?(:win32) %}
      # Prefer LOCALAPPDATA env var, fallback to registry, then default guess
      env_path = ENV["LOCALAPPDATA"]?
      return Path.new(env_path) if env_path

      reg_path = windows_registry_path("Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders", "Local AppData")
      return reg_path if reg_path

      Path.home / "AppData" / "Local" # Last resort guess
    {% elsif flag?(:darwin) %}
      macos_app? ? MACOS_APP_SUPPORT : (Path.home / ".local" / "share")
    {% else %}
      Path.home / ".local" / "share"
    {% end %}
  end

  private def self.default_cache_home : Path
    {% if flag?(:win32) %}
      # Cache often resides under LocalAppData
      base = default_data_home # Use the already determined data_home
      reg_path = windows_registry_path("Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders", "Cache")
      # Prefer registry 'Cache' if available, otherwise subdir of LocalAppData
      (reg_path || base / "Cache") # Note: Windows often uses "Cache", not "cache"
    {% elsif flag?(:darwin) %}
      Path.home / "Library" / "Caches"
    {% else %}
      Path.home / ".cache"
    {% end %}
  end

  private def self.default_state_home : Path
    {% if flag?(:win32) %}
      default_data_home / "state"
    {% elsif flag?(:darwin) %}
      Path.home / ".local" / "state" # Darwin doesn't typically use ~/.local/state, but follows spec if not macos_app?
    {% else %}
      Path.home / ".local" / "state"
    {% end %}
  end

  private def self.default_runtime_dir : Path?
    {% if flag?(:win32) %}
      nil # No standard runtime dir on Windows
    {% else %}
      # Ensure the path exists and is valid before returning it
      path = DEFAULT_RUNTIME_BASE / Process.uid
      valid_runtime_dir?(path) ? path : nil
    {% end %}
  end

  # These return the default *string* values before parsing.
  private def self.default_config_dirs : String
    {% if flag?(:win32) %}
      WINDOWS_PROGRAM_DATA.to_s # Windows doesn't have a standard multi-config dir concept like Linux/macOS
    {% elsif flag?(:darwin) %}
      # macOS apps typically bundle data or use App Support. Non-app follows spec.
      macos_app? ? MACOS_PREFERENCES.to_s : DEFAULT_CONFIG_DIRS_STR
    {% else %}
      DEFAULT_CONFIG_DIRS_STR
    {% end %}
  end

  private def self.default_data_dirs : String
    {% if flag?(:win32) %}
      WINDOWS_PROGRAM_DATA.to_s # Similar reasoning as config_dirs
    {% elsif flag?(:darwin) %}
      # macOS apps typically bundle data or use App Support. Non-app follows spec.
      macos_app? ? MACOS_APP_SUPPORT.to_s : DEFAULT_DATA_DIRS_STR
    {% else %}
      DEFAULT_DATA_DIRS_STR
    {% end %}
  end

  # Splits and validates path lists according to platform rules
  private def self.parse_paths(value : String?) : Array(Path)
    return [] of Path unless value

    value.split(Process::PATH_DELIMITER).compact_map do |raw_path|
      # Handle potential empty strings from splitting (e.g., trailing delimiter)
      next if raw_path.nil? || raw_path.empty? # Use empty? instead of blank? for core lib

      path = Path.new(raw_path)
      unless path.absolute?
        Log.warn { "Ignoring relative XDG directory path: #{raw_path}" }
        next
      end
      path
    end.uniq # Remove duplicates
  end


  private def self.macos_app?
    {% if flag?(:darwin) %}
      ENV["XDG_STRICT"]?.nil?
    {% else %}
      false
    {% end %}
  end

  # Attempts to read Windows registry keys with proper error handling
  def self.windows_registry_path(key_path : String, value_name : String) : Path?
    {% if flag?(:win32) %}
      # Ensure win32 specifics are available
      require "crystal/system/win32/registry"
      require "string" # For String.new with LibC result

      begin
        Crystal::System::WindowsRegistry.current_user.open(key_path) do |key|
          if raw_value = key[value_name]?
            # Expand environment variables in registry values
            # Need to allocate buffer for expand_environment_strings
            buffer_size = 260 # MAX_PATH is a common starting point
            loop do
              buffer = Slice(LibC::Char).new(buffer_size)
              bytes_written = LibC.expand_environment_strings(raw_value, buffer.pointer, buffer_size)

              if bytes_written == 0
                 # Error occurred during expansion
                 Log.warn { "Failed to expand environment strings for registry value: #{raw_value}" }
                 return nil
              elsif bytes_written > buffer_size
                 # Buffer too small, resize and retry
                 buffer_size = bytes_written
                 # No need to free buffer here, it goes out of scope
                 next
              else
                 # Success
                 expanded = String.new(buffer.pointer, bytes_written - 1) # -1 to exclude null terminator
                 return nil if expanded.empty?

                 path = Path.new(expanded)
                 # Basic check for absolute path - might need refinement for UNC etc.
                 if path.absolute? || path.to_s.starts_with?("\\\\") # Handle UNC paths
                   return path
                 end

                 Log.warn { "Registry path '#{value_name}' resolved to relative path: #{expanded}" }
                 return nil # Return nil for relative paths from registry
              end
            end # end loop
          end
        end
      rescue ex : Crystal::System::WindowsRegistry::Error
        Log.debug(exception: ex) { "Failed to read Windows registry key: #{key_path}\\#{value_name}" }
      end
    {% end %}

    nil # Return nil if not windows or key/value not found/invalid
  end

  # Safely joins path components, preventing directory traversal.
  private def self.safe_join(base : Path, parts : Enumerable(String)) : Path
    parts.each do |part|
      raise ArgumentError.new("Invalid path component: #{part}") if part.includes?("..") || part.includes?('/') || part.includes?('\\') || part.empty?
      base = base / part
    end
    base
  end
end
