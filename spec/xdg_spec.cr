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
