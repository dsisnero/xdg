require "./spec_helper"

# Define SpecHelpers module if it doesn't exist or add to it

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
    it "creates missing directories without validating existing ones" do
      in_temp_dir do |dir|
        with_xdg_clean_env do
          # Set one existing dir and one new dir
          existing_data_dir = File.join(dir, "existing_data")
          Dir.mkdir(existing_data_dir)
          File.chmod(existing_data_dir, 0o755) # "Wrong" permissions

          ENV["XDG_CONFIG_HOME"] = File.join(dir, "new_config") # Will be created
          ENV["XDG_DATA_HOME"] = existing_data_dir              # Already exists
          ENV["XDG_CACHE_HOME"] = File.join(dir, "cache")       # New
          ENV["XDG_STATE_HOME"] = File.join(dir, "state")       # New

          XDG.ensure_directories!(0o700)

          # Verify NEW directories get requested permissions
          (File.info(ENV["XDG_CONFIG_HOME"]).permissions.value & 0o777).should eq(0o700)
          (File.info(ENV["XDG_CACHE_HOME"]).permissions.value & 0o777).should eq(0o700)
          (File.info(ENV["XDG_STATE_HOME"]).permissions.value & 0o777).should eq(0o700)

          # Verify EXISTING directory kept original permissions
          (File.info(existing_data_dir).permissions.value & 0o777).should eq(0o755)
        end
      end
    end
  end

  describe "runtime directory validation" do
    it "creates new runtime directory with 0700 permissions" do
      in_temp_dir do |dir|
        runtime_dir = File.join(dir, "new_runtime")
        ENV["XDG_RUNTIME_DIR"] = runtime_dir

        XDG.runtime_dir!

        info = File.info(runtime_dir)
        actual_mode = info.permissions.value & 0o777
        actual_mode.should eq(0o700)
        info.owner_id.should eq(Process.uid.to_u64)
      ensure
        ENV.delete("XDG_RUNTIME_DIR")
      end
    end

    it "fixes existing directory permissions" do
      in_temp_dir do |dir|
        runtime_dir = File.join(dir, "existing_runtime")
        Dir.mkdir(runtime_dir, 0o755)
        ENV["XDG_RUNTIME_DIR"] = runtime_dir

        XDG.runtime_dir!

        actual_mode = File.info(runtime_dir).permissions.value & 0o777
        actual_mode.should eq(0o700)
      ensure
        ENV.delete("XDG_RUNTIME_DIR")
      end
    end

    it "rejects invalid ownership" do
      in_temp_dir do |dir|
        runtime_dir = File.join(dir, "bad_owner")
        Dir.mkdir(runtime_dir, 0o700)

        # Skip test if we can't simulate wrong ownership
        # Note: Changing ownership often requires root privileges.
        # This test might only pass if run as root or if the OS allows user chown.
        can_chown = begin
          File.chown(runtime_dir, uid: Process.uid.to_u64 + 1)
          true # Chown succeeded
        rescue
          false # Chown failed (likely permission denied)
        end

        unless can_chown
          puts "Skipping ownership test: Cannot change file ownership (requires root or specific capabilities)."
          next # Skip the rest of this 'it' block
        end

        # If chown succeeded, proceed with the test
        ENV["XDG_RUNTIME_DIR"] = runtime_dir

        expect_raises(XDG::SecurityError) do
          XDG.runtime_dir!
        end
      ensure
        # Clean up: Attempt to restore ownership if possible, ignore errors
        begin
        if runtime_dir
          File.chown(runtime_dir, uid: Process.uid.to_u64) if can_chown && Dir.exists?(runtime_dir)
        end
        rescue
        end
        ENV.delete("XDG_RUNTIME_DIR")
      end
    end

    it "rejects non-directory paths" do
      in_temp_dir do |dir|
        runtime_file = File.join(dir, "file")
        File.write(runtime_file, "")
        ENV["XDG_RUNTIME_DIR"] = runtime_file

        expect_raises(XDG::SecurityError) do
          XDG.runtime_dir!
        end
      ensure
        ENV.delete("XDG_RUNTIME_DIR")
      end
    end

    it "validates permissions after creation" do
      in_temp_dir do |dir|
        runtime_dir = File.join(dir, "creation_test")
        ENV["XDG_RUNTIME_DIR"] = runtime_dir

        # First call creates and validates
        XDG.runtime_dir!

        # Tamper with permissions *after* the initial successful creation/validation
        File.chmod(runtime_dir, 0o750) # Make it insecure

        # Second call should detect the insecure state and raise SecurityError
        expect_raises(XDG::SecurityError) do
          XDG.runtime_dir!
        end
      ensure
        ENV.delete("XDG_RUNTIME_DIR")
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
    # Note: ensure_directories! no longer validates existing directories.
    # Validation is primarily done by valid_directory? and valid_runtime_dir?

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
          XDG.valid_directory?(test_dir, 0o755).should be_true  # Passes 755 <= 755
        else
          puts "Skipping permission max test due to owner mismatch (UID: #{Process.uid}, Owner: #{File.info(test_dir.to_s).owner_id})"
        end
      end
    end
  end

  describe "existing directory handling" do
    it "writes to existing directory with non-0700 permissions" do
      in_temp_dir do |dir|
        with_xdg_clean_env do
          ENV["XDG_CONFIG_HOME"] = File.join(dir, "config")
          Dir.mkdir(ENV["XDG_CONFIG_HOME"], 0o755) # "Insecure" dir

          path = XDG.app_config_path("test.txt", create: true)
          File.write(path, "data") # Should succeed despite dir perms
          File.read(path).should eq("data")
        end
      end
    end

    it "preserves existing directory permissions when creating files" do
      in_temp_dir do |dir|
        with_xdg_clean_env do
          ENV["XDG_CACHE_HOME"] = File.join(dir, "cache")
          original_mode = 0o755
          Dir.mkdir(ENV["XDG_CACHE_HOME"], original_mode)

          XDG.app_cache_path("data.bin", create: true)
          new_mode = File.info(ENV["XDG_CACHE_HOME"]).permissions.value & 0o777
          new_mode.should eq(original_mode)
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
