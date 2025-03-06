# xdg

Crystal implementation of the XDG Base Directory Specification with cross-platform support (Linux, macOS, Windows)

Provides standardized access to application configuration, data, and cache directories while respecting platform conventions and environment variables.

## Installation

1. Add the dependency to your `shard.yml`:

```yaml
dependencies:
  xdg:
    github: dsisnero/xdg
```

2. Run `shards install`

## Usage

```crystal
require "xdg"

# Access base directories
config_path = XDG.config_home    # => ~/.config (Linux), ~/Library/Preferences (macOS), etc
data_path = XDG.data_home        # => ~/.local/share (Linux), ~/Library/Application Support (macOS), etc
cache_path = XDG.cache_home      # => ~/.cache (Linux), ~/Library/Caches (macOS), etc

# Platform-aware path construction
app_config = XDG.app_config("myapp", "1.0", vendor: "acme")
# => ~/.config/acme/myapp/1.0 (Linux)
# => ~/Library/Preferences/acme/myapp/1.0 (macOS App)
# => %APPDATA%\acme\myapp\1.0 (Windows)

# Ensure directories exist with secure permissions
XDG.ensure_directories!(0o750)

# Validate runtime directories
if runtime_dir = XDG.runtime_dir
  puts "Secure runtime: #{XDG.valid_runtime_dir?(runtime_dir)}"
end
```

**Platform Support**:
- Linux: Follows XDG spec defaults
- macOS: Uses native paths unless in strict mode (`XDG_STRICT=true`)
- Windows: Uses APPDATA/LOCALAPPDATA environment variables

## Development

1. Clone the repo: `git clone https://github.com/dsisnero/xdg.git`
2. Install dependencies: `shards install`
3. Run tests: `crystal spec`

Key components:
- `src/xdg.cr`: Core implementation
- `spec/xdg_spec.cr`: Comprehensive test suite
- Platform-specific logic handled through compile-time flags

## Contributing

1. Fork it (<https://github.com/dsisnero/xdg/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

**Please include**:
- Spec tests for new features
- Updates to documentation when applicable
- Cross-platform verification

## Contributors

- [Dominic Sisneros](https://github.com/dsisnero) - creator and maintainer
