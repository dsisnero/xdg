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
# Creates parent directories with 0700 permissions if missing
config_file = XDG.app_config_path("myapp.cfg", create: true)

# Writes file with automatic directory creation (0700 for new dirs)
File.write(config_file, config_data) rescue puts "Save failed"

# Runtime directory security (must be 0700)
runtime_dir = XDG.runtime_dir! # Raises if permissions wrong
```

Key features:
- Automatic directory creation with 0700 permissions
- Existing directories remain untouched
- Strict security checks only for runtime directory
- Clean error hierarchy (XDG::Error > DirectoryError/SecurityError)

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
