![kk-logo](https://user-images.githubusercontent.com/1652790/203277328-23457c63-5073-4b9d-9c0c-090c5d7878a2.png)

`kk` is a new `ls` substitute for `zsh` forked from `k`.


[kk](https://github.com/dongminkim/kk) is a project that seek to aggressively refactor [k](https://github.com/supercrabtree/k)*\** in order to:

- Improve execution speed
- Improve compatibilities with the genuine `ls`
- Improve user experiences


## Usage

- `kk -a`

  <img width="502" alt="kk -a" src="https://github.com/user-attachments/assets/069f5209-1212-4645-b4a4-13aac6579ea2" />

- Find more at [the wiki page](https://github.com/dongminkim/kk/wiki#sample-usage)


## Architecture

As of the latest version, `kk` has been refactored into a modular architecture for better maintainability and testability:

```
kk/
├── kk.plugin.zsh       # Main entry point (112 lines)
├── lib/                # Core library modules
│   ├── utils.zsh      # Common utility functions
│   ├── options.zsh    # Command-line option parsing
│   ├── sort.zsh       # Sort configuration
│   ├── colors.zsh     # Color definitions and initialization
│   ├── files.zsh      # File collection logic
│   ├── stat.zsh       # File stat processing
│   ├── git.zsh        # Git integration
│   └── format.zsh     # Output formatting
└── tests/              # Test framework
    ├── run-tests.zsh
    ├── test-options.zsh
    ├── test-sort.zsh
    ├── test-colors.zsh
    └── test-format.zsh
```

### Benefits of Modular Design

- **Maintainability**: Each module is 50-200 lines instead of a 600+ line monolith
- **Testability**: Individual functions can be tested independently
- **Extensibility**: Easy to add new features or modify existing behavior
- **Clarity**: Clear separation of concerns makes the codebase easier to understand

## Sample Test Directory

- `tar zxf test-dir.tgz`

## Development

### Running Tests

```bash
# Run all tests
zsh tests/run-tests.zsh

# Or make it executable and run directly
chmod +x tests/run-tests.zsh
./tests/run-tests.zsh
```

### Testing Manually

```bash
# Source the plugin
source kk.plugin.zsh

# Test basic functionality
kk

# Test with options
kk -a
kk -h
kk -t
kk --no-vcs

# Test on test directory
cd test-dir
kk
```

### Module Overview

- **utils.zsh**: Utility functions (`debug`, `_kk_bsd_to_ansi`, `_kk_init_locals`)
- **options.zsh**: Option parsing with `zparseopts`, validation, and help text
- **sort.zsh**: Translates sort options to zsh glob qualifiers
- **colors.zsh**: Color initialization for file types, sizes, and ages
- **files.zsh**: File collection using glob patterns
- **stat.zsh**: File stat processing with `zstat` and human-readable sizes
- **git.zsh**: Git repository detection and status collection
- **format.zsh**: Output formatting with colors and Git status markers

### Contributing

When contributing, please:

1. Follow the existing code style
2. Add tests for new functionality
3. Run tests before submitting PR: `zsh tests/run-tests.zsh`
4. Keep functions focused and modules small
5. Use `_kk_` prefix for all internal functions

## License

MIT License


----
*\* [supercrabtree/k](https://github.com/supercrabtree/k) seems to be no longer being managed.*
