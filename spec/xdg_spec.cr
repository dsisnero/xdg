require "./spec_helper"

include SpecHelpers

describe XDG do
  # Specialized helper for runtime directory creation

  describe "base directory accessors" do
    {% for dir in %w[config data cache state] %}
      it "returns {{dir.id}}_home Path from environment" do
        with_xdg_clean_env do
          ENV["XDG_{{dir.id.upcase}}_HOME"] = "/custom/{{dir.id}}"
          XDG.{{dir.id}}_home.should eq Path["/custom/{{dir.id}}"]
        end
      end
    {% end %}
  end

  describe "application paths" do
    it "generates versioned config paths correctly" do
      with_xdg_clean_env do
        ENV["XDG_CONFIG_HOME"] = "/test/config"
        ENV["XDG_STATE_HOME"] = "/test/state"
        XDG.app_config("myapp", "1.2.3").should eq Path["/test/config/myapp/1.2.3"]
        XDG.app_state("myapp", "2.0").should eq Path["/test/state/myapp/2.0"]
      end
    end

    it "supports vendor namespaces correctly" do
      with_xdg_clean_env do
        ENV["XDG_CONFIG_HOME"] = "/test/config"
        path = XDG.app_config("cli", vendor: "acme")
        path.should eq Path["/test/config/acme/cli"]
      end
    end
  end

  describe "directory management" do
    it "creates secure directories with correct permissions" do
      in_temp_dir do |dir|
        with_xdg_clean_env do
          ENV["XDG_CONFIG_HOME"] = File.join(dir, "config")
          ENV["XDG_DATA_HOME"] = File.join(dir, "data")
          ENV["XDG_CACHE_HOME"] = File.join(dir, "cache")
          ENV["XDG_STATE_HOME"] = File.join(dir, "state")

          XDG.ensure_directories!(0o750)

          [ENV["XDG_CONFIG_HOME"], ENV["XDG_DATA_HOME"], ENV["XDG_CACHE_HOME"], ENV["XDG_STATE_HOME"]].each do |path|
            info = File.info(path)
            info.permissions.should eq File::Permissions.new(0o750)
            info.directory?.should be_true
          end
        end
      end
    end
  end

  describe "runtime directory validation" do
    it "rejects world-writable directories" do
      in_temp_dir do |dir|
        bad_dir = File.join(dir, "unsafe")
        # Create with safe permissions first
        Dir.mkdir(bad_dir, 0o755)
        # Then make world-writable
        File.chmod(bad_dir, 0o777)

        XDG.valid_runtime_dir?(Path.new(bad_dir)).should be_false
      end
    end

   it "accepts properly secured directories" do
     in_temp_dir do |dir|
       valid_dir = File.join(dir, "secure")
       create_runtime_dir(valid_dir) # Uses the helper from spec_helper

       # create_runtime_dir already handles permissions and ownership.
       # Simplify ownership check - remove unnecessary chown attempts
       XDG.valid_runtime_dir?(Path.new(valid_dir)).should be_true
     end
   end
  end

  describe "platform defaults" do
    context "on Windows", tags: "windows" do
      it "uses APPDATA for config home" do
        with_xdg_clean_env do
          {% if flag?(:win32) %}
            expected_path = Path[ENV["APPDATA"]? || File.join(Dir.home, "AppData", "Roaming")]
            XDG.config_home.should eq expected_path
            XDG.config_dirs.should eq [XDG::WINDOWS_PROGRAM_DATA] # Should be an array containing the path
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
            XDG.config_home.basename.should eq ".config"
            XDG.data_home.basename.should eq "share"
            XDG.data_home.parent.basename.should eq ".local"
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
            XDG.config_dirs.should eq [Path["/etc/xdg"]]
            XDG.data_dirs.should eq [Path["/usr/local/share"], Path["/usr/share"]]
            XDG.state_home.should eq Path.home / ".local" / "state"
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
          XDG.data_dirs.should eq [Path["C:\\Data1"], Path["C:\\Data2"]]
        {% else %}
          pending! "Windows path test"
        {% end %}
      end
    end

    it "handles UNIX-style list separators", tags: "linux macos" do
      with_xdg_clean_env do
        ENV["XDG_CONFIG_DIRS"] = "/etc/config:/usr/local/config"
        # On Windows, the delimiter might be ';', but the test environment might not reflect that.
        # The code uses Process::PATH_DELIMITER which should be correct for the OS.
        # Let's assume POSIX delimiter for non-Windows test runs.
        {% if flag?(:win32) %}
          ENV["XDG_CONFIG_DIRS"] = "C:\\Config1;C:\\Config2" # Use Windows style for test
          XDG.config_dirs.should eq [Path["C:\\Config1"], Path["C:\\Config2"]]
        {% else %}
           XDG.config_dirs.should eq [Path["/etc/config"], Path["/usr/local/config"]]
        {% end %}
      end
    end
  end

  describe "path security validation" do
    it "rejects directories with excessive permissions in ensure_directories!" do
      in_temp_dir do |dir|
        with_xdg_clean_env do
          # Only set the problematic directory to isolate the test
          ENV["XDG_DATA_HOME"] = File.join(dir, "data")
          # Other XDG vars (CONFIG_HOME, CACHE_HOME, STATE_HOME) are needed by ensure_directories!
          # but we don't need to assign them specific paths for this test's purpose.
          # Let them default or be nil, ensure_directories! will handle them.
          # We only care about the state of XDG_DATA_HOME which we explicitly make insecure.
          ENV["XDG_CONFIG_HOME"] = File.join(dir, "config") # Still needed for the call
          ENV["XDG_CACHE_HOME"] = File.join(dir, "cache")   # Still needed for the call
          ENV["XDG_STATE_HOME"] = File.join(dir, "state")   # Still needed for the call


          # Create directory and explicitly set permissions
          insecure_dir = ENV["XDG_DATA_HOME"]
          Dir.mkdir(insecure_dir)
          File.chmod(insecure_dir, 0o777) # <-- Force exact permissions

          # ensure_directories! should check existing dirs too and raise on the insecure one
          expect_raises(XDG::SecurityError, /Permissions 777 exceed expected <= 700/) do
            XDG.ensure_directories!(mode: 0o700) # Requesting 700
          end

          # Only check the problematic directory's permissions remain unchanged (or were not fixed)
          # The other directories might or might not have been created depending on iteration order.
          info = File.info(insecure_dir)
          (info.permissions.value & 0o777).should_not eq(0o700)
          # Verify it still exists and has the insecure permissions
          Dir.exists?(insecure_dir).should be_true
          (info.permissions.value & 0o777).should eq(0o777)
        end
      end
    end

    it "rejects world-writable directories via valid_directory?" do
       in_temp_dir do |dir|
         test_dir = Path[dir] / "world_writable"
         Dir.mkdir(test_dir.to_s, 0o777)
         XDG.valid_directory?(test_dir, 0o755).should be_false # Fails due to world-writable bit
       end
    end

    it "rejects directories with permissions higher than max allowed via valid_directory?" do
       in_temp_dir do |dir|
         test_dir = Path[dir] / "too_permissive"
         # Create with 755, but validate against 700 max
         Dir.mkdir(test_dir.to_s, 0o755)
         # Need to ensure owner matches current user for the test to be reliable on permissions
         # File.chown(nil, Process.uid.to_i, test_dir.to_s) # chown might require root

         # Assuming owner is correct, check permissions
         # This test might be flaky if owner isn't current user in CI
         if File.info(test_dir.to_s).owner_id == Process.uid.to_i
           XDG.valid_directory?(test_dir, 0o700).should be_false # Fails 755 > 700
           XDG.valid_directory?(test_dir, 0o755).should be_true # Passes 755 <= 755
         else
           puts "Skipping permission max test due to owner mismatch (UID: #{Process.uid}, Owner: #{File.info(test_dir.to_s).owner_id})"
         end
       end
    end
  end

  describe "windows registry fallbacks", tags: "windows" do
    it "reads AppData from registry" do
      {% if flag?(:win32) %}
        # Mock registry would be better, but check integration
        # This relies on the standard registry keys existing
        path = XDG.send(:windows_registry_path,
          "Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders",
          "AppData" # This usually points to Roaming AppData
        )
        # We can't guarantee it exists, but if it does, it should be absolute
        if path
           path.should be_a(Path)
           path.should be_absolute
           # Check if it looks like a plausible AppData path
           path.to_s.should contain("AppData\\Roaming")
        else
           puts "Skipping Windows registry check for AppData: Key or value not found."
           # Allow test to pass if key is missing, as it's environment-dependent
        end
      {% else %}
        pending! "Windows-only test"
      {% end %}
    end

     it "reads Local AppData from registry" do
       {% if flag?(:win32) %}
         path = XDG.send(:windows_registry_path,
           "Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders",
           "Local AppData"
         )
         if path
           path.should be_a(Path)
           path.should be_absolute
           path.to_s.should contain("AppData\\Local")
         else
           puts "Skipping Windows registry check for Local AppData: Key or value not found."
         end
       {% else %}
         pending! "Windows-only test"
       {% end %}
     end

     it "handles non-existent registry keys gracefully" do
       {% if flag?(:win32) %}
         path = XDG.send(:windows_registry_path,
           "Software\\NonExistentApp\\FakeKey",
           "FakeValue"
         )
         path.should be_nil
       {% else %}
         pending! "Windows-only test"
       {% end %}
     end
  end

  # - find_config_file (found, not found, invalid name)
  # - app_config_path, app_data_path etc. (with/without create, error handling, invalid names)
  # - ensure_directories! (more error handling scenarios)
  # - Path sanitization in app_config/app_state (ArgumentError for '..', '/', empty)
  # - valid_directory? helper (more edge cases, group/other permissions)
  # - valid_runtime_dir? (more edge cases)
end
