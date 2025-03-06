 module XDG
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

   # Returns the XDG_RUNTIME_DIR directory path or nil
   def self.runtime_dir : String?
     ENV["XDG_RUNTIME_DIR"]? || default_runtime_dir
   end

   # Ensures all XDG base directories exist
   def self.ensure_directories : Nil
     [config_home, data_home, cache_home].each do |dir|
       Dir.mkdir_p(dir) unless Dir.exists?(dir)
     end
   end

   private def self.default_config_home : String
     {% if flag?(:win32) %}
       File.join(ENV["APPDATA"], "config")
     {% else %}
       File.join(Dir.home, ".config")
     {% end %}
   end

   private def self.default_data_home : String
     {% if flag?(:win32) %}
       File.join(ENV["LOCALAPPDATA"], "data")
     {% else %}
       File.join(Dir.home, ".local", "share")
     {% end %}
   end

   private def self.default_cache_home : String
     {% if flag?(:win32) %}
       File.join(ENV["LOCALAPPDATA"], "cache")
     {% else %}
       File.join(Dir.home, ".cache")
     {% end %}
   end

   private def self.default_runtime_dir : String?
     {% if flag?(:win32) %}
       nil
     {% else %}
       "/run/user/#{Process.uid}"
     {% end %}
   end
 end
