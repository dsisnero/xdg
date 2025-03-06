require "./spec_helper"

describe Xdg do
  # TODO: Write tests

  it "works" do
    false.should eq(true)
  end
end
require "./spec_helper"
require "file_utils"
require "tempfile"

describe XDG do
  # Test helpers for cross-platform testing
  module TestHelpers
    def with_clean_env
      original_env = ENV.to_h
      {% for var in %w[XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME
                      XDG_CONFIG_DIRS XDG_DATA_DIRS XDG_RUNTIME_DIR XDG_STRICT] %}
        ENV.delete({{var}})
      {% end %}
      yield
    ensure
      ENV.clear
      original_env.each { |k, v| ENV[k] = v }
    end

    def in_temp_dir(&block)
      Tempfile.open("xdg_spec") do |file|
        dir = file.path
        FileUtils.rm_rf(dir)
        FileUtils.mkdir_p(dir)
        Dir.cd(dir) { yield(dir) }
      end
    end

    def create_runtime_dir(path : String, uid : Int32? = nil)
      FileUtils.mkdir_p(path)
      File.chmod(path, 0o700)
      if uid
        File.chown(path, uid: Process.uid, gid: Process.gid)
      end
    end
  end

  include TestHelpers

  describe "base directory accessors" do
    {% for dir in %w[config data cache state] %}
      it "returns #{dir}_home from environment" do
        with_clean_env do
          ENV["XDG_{{dir.id.upcase}}_HOME"] = "/custom/{{dir.id}}"
          XDG.{{dir.id}}_home.should eq "/custom/{{dir.id}}"
        end
      end
    {% end %}
  end

  describe "application-specific paths" do
    it "generates versioned paths" do
      with_clean_env do
        path = XDG.app_config("myapp", "1.0")
        path.should end_with(File.join("myapp", "1.0"))
        
        state_path = XDG.app_state("myapp", "2.0")
        state_path.should end_with(File.join("myapp", "2.0"))
      end
    end

    it "supports vendor namespaces" do
      with_clean_env do
        path = XDG.app_config("myapp", vendor: "acme")
        path.should end_with(File.join("acme", "myapp"))
      end
    end
  end

  describe "directory management" do
    it "creates directories with correct permissions" do
      in_temp_dir do |dir|
        with_clean_env do
          ENV["XDG_CONFIG_HOME"] = File.join(dir, "config")
          XDG.ensure_directories!(0o750)
          
          File.info(ENV["XDG_CONFIG_HOME"]).permissions.should eq File::Permissions.new(0o750)
        end
      end
    end
  end

  describe "runtime directory validation" do
    it "rejects invalid directories" do
      in_temp_dir do |dir|
        invalid_dir = File.join(dir, "invalid")
        FileUtils.mkdir_p(invalid_dir)
        File.chmod(invalid_dir, 0o777)
        
        XDG.valid_runtime_dir?(invalid_dir).should be_false
      end
    end

    it "accepts valid directories" do
      in_temp_dir do |dir|
        valid_dir = File.join(dir, "valid")
        create_runtime_dir(valid_dir)
        
        XDG.valid_runtime_dir?(valid_dir).should be_true
      end
    end
  end

  describe "platform-specific behavior" do
    context "on Windows" do
      it "uses PROGRAMDATA for system directories", tags: "windows" do
        with_clean_env do
          {% if flag?(:win32) %}
            XDG.config_dirs.should contain(XDG::WINDOWS_PROGRAM_DATA)
            XDG.data_dirs.should contain(XDG::WINDOWS_PROGRAM_DATA)
          {% else %}
            pending! "Windows-only test"
          {% end %}
        end
      end
    end

    context "on macOS" do
      it "respects XDG_STRICT environment variable", tags: "macos" do
        with_clean_env do
          {% if flag?(:darwin) %}
            ENV["XDG_STRICT"] = "1"
            XDG.config_home.should end_with(".config")
            XDG.data_home.should end_with(".local/share")
          {% else %}
            pending! "macOS-only test"
          {% end %}
        end
      end
    end

    context "on Linux/Unix" do
      it "follows XDG base directory spec", tags: "linux" do
        with_clean_env do
          {% if !flag?(:win32) && !flag?(:darwin) %}
            XDG.config_dirs.should eq ["/etc/xdg"]
            XDG.data_dirs.should eq ["/usr/local/share", "/usr/share"]
          {% else %}
            pending! "Linux-only test"
          {% end %}
        end
      end
    end
  end

  describe "multi-directory handling" do
    it "parses Windows-style paths", tags: "windows" do
      with_clean_env do
        ENV["XDG_CONFIG_DIRS"] = "C:\\Config1;C:\\Config2"
        {% if flag?(:win32) %}
          XDG.config_dirs.should eq ["C:\\Config1", "C:\\Config2"]
        {% else %}
          pending! "Windows path test"
        {% end %}
      end
    end

    it "parses UNIX-style paths", tags: "linux macos" do
      with_clean_env do
        ENV["XDG_DATA_DIRS"] = "/data1:/data2"
        XDG.data_dirs.should eq ["/data1", "/data2"]
      end
    end
  end
end
require "./spec_helper"

describe XDG do
  # Add runtime dir specific helper
  def create_runtime_dir(path : String)
    parent = File.dirname(path)
    Dir.mkdir_p(parent) unless Dir.exists?(parent)
    
    Dir.mkdir(path)
    File.chmod(path, 0o700)
    File.chown(path, uid: Process.uid, gid: Process.gid)
  end

  describe "base directories" do
    it "uses temporary directories in tests" do
      in_temp_dir do |dir|
        # Test that uses temp dir
        XDG.config_home.should start_with(dir)
      end
    end
  end

  # ... rest of specs ...
end
require "./spec_helper"

describe XDG do
  # Specialized helper for runtime directory creation
  def create_runtime_dir(path : String)
    parent = File.dirname(path)
    Dir.mkdir_p(parent) unless Dir.exists?(parent)
    
    Dir.mkdir(path)
    File.chmod(path, 0o700)
    File.chown(path, uid: Process.uid, gid: Process.gid)
  end

  describe "base directory accessors" do
    {% for dir in %w[config data cache state] %}
      it "returns #{dir}_home from environment" do
        with_xdg_clean_env do
          ENV["XDG_{{dir.id.upcase}}_HOME"] = "/custom/{{dir.id}}"
          XDG.{{dir.id}}_home.should eq "/custom/{{dir.id}}"
        end
      end
    {% end %}
  end

  describe "application paths" do
    it "generates versioned config paths" do
      with_xdg_clean_env do
        XDG.app_config("myapp", "1.2.3").should end_with("myapp/1.2.3")
      end
    end

    it "creates vendor namespaced paths" do
      with_xdg_clean_env do
        path = XDG.app_config("cli", vendor: "acme")
        path.should end_with("acme/cli")
      end
    end
  end

  describe "directory management" do
    it "creates secure directories" do
      in_temp_dir do |dir|
        with_xdg_clean_env do
          ENV["XDG_DATA_HOME"] = File.join(dir, "data")
          XDG.ensure_directories!(0o750)
          
          info = File.info(ENV["XDG_DATA_HOME"])
          info.permissions.should eq File::Permissions.new(0o750)
          info.directory?.should be_true
        end
      end
    end
  end

  describe "runtime validation" do
    it "rejects world-writable directories" do
      in_temp_dir do |dir|
        bad_dir = File.join(dir, "unsafe")
        Dir.mkdir(bad_dir)
        File.chmod(bad_dir, 0o777)
        
        XDG.valid_runtime_dir?(bad_dir).should be_false
      end
    end

    it "accepts properly secured directories" do
      in_temp_dir do |dir|
        valid_dir = File.join(dir, "secure")
        create_runtime_dir(valid_dir)
        
        XDG.valid_runtime_dir?(valid_dir).should be_true
      end
    end
  end

  describe "platform defaults" do
    context "on Windows", tags: "windows" do
      it "uses APPDATA for config home" do
        with_xdg_clean_env do
          {% if flag?(:win32) %}
            expected = ENV["APPDATA"]? || File.join(Dir.home, "AppData", "Roaming")
            XDG.config_home.should eq expected
          {% else %}
            pending! "Windows-only test"
          {% end %}
        end
      end
    end

    context "on macOS", tags: "macos" do
      it "respects XDG_STRICT mode" do
        with_xdg_clean_env do
          {% if flag?(:darwin) %}
            ENV["XDG_STRICT"] = "true"
            XDG.data_home.should end_with(".local/share")
          {% else %}
            pending! "macOS-only test"
          {% end %}
        end
      end
    end

    context "on Linux", tags: "linux" do
      it "follows base spec defaults" do
        with_xdg_clean_env do
          {% if !flag?(:win32) && !flag?(:darwin) %}
            XDG.config_dirs.should eq ["/etc/xdg"]
            XDG.state_home.should end_with(".local/state")
          {% else %}
            pending! "Linux-only test"
          {% end %}
        end
      end
    end
  end

  describe "path parsing" do
    it "handles Windows-style list separators" do
      with_xdg_clean_env do
        ENV["XDG_DATA_DIRS"] = "C:\\Data1;C:\\Data2"
        {% if flag?(:win32) %}
          XDG.data_dirs.should eq ["C:\\Data1", "C:\\Data2"]
        {% else %}
          pending! "Windows path test"
        {% end %}
      end
    end

    it "handles UNIX-style list separators" do
      with_xdg_clean_env do
        ENV["XDG_CONFIG_DIRS"] = "/etc/config:/usr/local/config"
        XDG.config_dirs.should eq ["/etc/config", "/usr/local/config"]
      end
    end
  end
end
