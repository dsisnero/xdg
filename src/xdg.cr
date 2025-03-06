class Process

  def self.uid
    LibC.getuid.to_s
  end

end
     
module XDG
  # Constants for platform-specific paths
  MACOS_APP_SUPPORT    = File.join(Path.home, "Library", "Application Support")
  MACOS_PREFERENCES    = File.join(Path.home, "Library", "Preferences")
  WINDOWS_PROGRAM_DATA = ENV["PROGRAMDATA"]? || "C:\\ProgramData"

  # Returns the XDG_CONFIG_HOME directory path
  def self.config_home : String
    ENV["XDG_CONFIG_HOME"]? || default_config_home
  end

  # Returns the XDG_DATA_HOME directory path
  def self.data_home : String
    ENV["XDG_DATA_HOME"]? || default_data_home
  end

  # Returns the XDG_CACHE_HOME directory path
  def self.cache_home : String
    ENV["XDG_CACHE_HOME"]? || default_cache_home
  end

  # Returns the XDG_STATE_HOME directory path
  def self.state_home : String
    ENV["XDG_STATE_HOME"]? || default_state_home
  end

  # Returns the XDG_RUNTIME_DIR directory path or nil
  def self.runtime_dir : String?
    ENV["XDG_RUNTIME_DIR"]? || default_runtime_dir
  end

  # Returns an array of XDG_CONFIG_DIRS paths
  def self.config_dirs : Array(String)
    parse_paths(ENV["XDG_CONFIG_DIRS"]? || default_config_dirs)
  end

  # Returns an array of XDG_DATA_DIRS paths
  def self.data_dirs : Array(String)
    parse_paths(ENV["XDG_DATA_DIRS"]? || default_data_dirs)
  end

  # Returns a config path for a specific application
  def self.app_config(app : String, version : String? = nil, vendor : String? = nil) : String
    base = vendor ? File.join(config_home, vendor) : config_home
    version ? File.join(base, app, version) : File.join(base, app)
  end

  # Returns a state path for a specific application
  def self.app_state(app : String, version : String? = nil) : String
    version ? File.join(state_home, app, version) : File.join(state_home, app)
  end

  # Ensures all XDG base directories exist
  def self.ensure_directories : Nil
    [config_home, data_home, cache_home].each do |dir|
      Dir.mkdir_p(dir) unless Dir.exists?(dir)
    end
  end

  # Ensures all XDG base directories exist with specific permissions
  def self.ensure_directories!(mode : Int32 = 0o700)
    [config_home, data_home, cache_home, state_home].each do |dir|
      Dir.mkdir_p(dir, mode) unless Dir.exists?(dir)
    end
  end

  # Validates if a runtime directory meets XDG security requirements
  def self.valid_runtime_dir?(path : String) : Bool
    return false unless Dir.exists?(path)
    
    info = File.info(path)
    return false unless info.directory?
  
    # Check for proper permissions and ownership
    current_uid = Process.uid
    info.permissions.other_write? == false &&
      info.owner_id == current_uid &&
      info.group_id == current_uid
  end

  private def self.default_config_home : String
    {% if flag?(:win32) %}
      ENV["APPDATA"]? || File.join(Path.home, "AppData", "Roaming")
    {% elsif flag?(:darwin) %}
      macos_app? ? MACOS_PREFERENCES : File.join(Path.home, ".config")
    {% else %}
      File.join(Path.home, ".config")
    {% end %}
  end

  private def self.default_data_home : String
    {% if flag?(:win32) %}
      ENV["LOCALAPPDATA"]? || File.join(Path.home, "AppData", "Local")
    {% elsif flag?(:darwin) %}
      macos_app? ? MACOS_APP_SUPPORT : File.join(Path.home, ".local", "share")
    {% else %}
      File.join(Path.home, ".local", "share")
    {% end %}
  end

  private def self.default_cache_home : String
    {% if flag?(:win32) %}
      File.join(ENV["LOCALAPPDATA"]? || File.join(Path.home, "AppData", "Local"), "cache")
    {% elsif flag?(:darwin) %}
      File.join(Path.home, "Library", "Caches")
    {% else %}
      File.join(Path.home, ".cache")
    {% end %}
  end

  private def self.default_state_home : String
    {% if flag?(:win32) %}
      File.join(default_data_home, "state")
    {% elsif flag?(:darwin) %}
      File.join(Path.home, ".local", "state")
    {% else %}
      File.join(Path.home, ".local", "state")
    {% end %}
  end

  private def self.default_runtime_dir : String?
    {% if flag?(:win32) %}
      nil
    {% else %}
      "/run/user/#{Process.uid}"
    {% end %}
  end

  private def self.default_config_dirs : String
    {% if flag?(:win32) %}
      WINDOWS_PROGRAM_DATA
    {% elsif flag?(:darwin) %}
      macos_app? ? MACOS_APP_SUPPORT : "/etc/xdg"
    {% else %}
      "/etc/xdg"
    {% end %}
  end

  private def self.default_data_dirs : String
    {% if flag?(:win32) %}
      WINDOWS_PROGRAM_DATA
    {% elsif flag?(:darwin) %}
      MACOS_APP_SUPPORT
    {% else %}
      "/usr/local/share:/usr/share"
    {% end %}
  end

  private def self.parse_paths(value : String?) : Array(String)
     return [] of String  unless value
     value.split(Process::PATH_DELIMITER)
  end

  private def self.macos_app?
    {% if flag?(:darwin) %}
      ENV["XDG_STRICT"]?.nil?
    {% else %}
      false
    {% end %}
  end
end
