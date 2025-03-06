require "./spec_helper"

describe XDG do
  # Specialized helper for runtime directory creation


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
        XDG.app_state("myapp", "2.0").should end_with("myapp/2.0")
      end
    end

    it "supports vendor namespaces" do
      with_xdg_clean_env do
        path = XDG.app_config("cli", vendor: "acme")
        path.should end_with("acme/cli")
      end
    end
  end

  describe "directory management" do
    it "creates secure directories with correct permissions" do
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

  describe "runtime directory validation" do
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
            XDG.config_dirs.should contain(XDG::WINDOWS_PROGRAM_DATA)
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
            XDG.config_home.should end_with(".config")
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
            XDG.data_dirs.should eq ["/usr/local/share", "/usr/share"]
            XDG.state_home.should end_with(".local/state")
          {% else %}
            pending! "Linux-only test"
          {% end %}
        end
      end
    end
  end

  describe "path parsing" do
    it "handles Windows-style list separators", tags: "windows" do
      with_xdg_clean_env do
        ENV["XDG_DATA_DIRS"] = "C:\\Data1;C:\\Data2"
        {% if flag?(:win32) %}
          XDG.data_dirs.should eq ["C:\\Data1", "C:\\Data2"]
        {% else %}
          pending! "Windows path test"
        {% end %}
      end
    end

    it "handles UNIX-style list separators", tags: "linux macos" do
      with_xdg_clean_env do
        ENV["XDG_CONFIG_DIRS"] = "/etc/config:/usr/local/config"
        XDG.config_dirs.should eq ["/etc/config", "/usr/local/config"]
      end
    end
  end
end
