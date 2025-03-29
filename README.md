# gdunit4.nvim

A Neovim plugin for integrating GdUnit4 (Godot testing framework) with Neovim. Run, debug, and generate tests for your Godot projects without leaving your editor!
# WARNING (this is only tested on my machine arch linux and nvim v0.10.4)

## Features

- 🧪 Run GdUnit4 tests directly from Neovim
- 🔍 Display test results with syntax highlighting
- ✨ Generate test templates for C# classes
- ⚙️ Configure test runs with custom options
- 📊 View test reports in a floating window
- 🔄 Integration with snacks.nvim for enhanced UI

## Prerequisites

- Neovim 0.8.0 or higher
- [Godot](https://godotengine.org/) with GdUnit4 addon installed
- [Treesitter](https://github.com/nvim-treesitter/nvim-treesitter) with C# and XML parsers installed

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "jamesonBradfield/gdunit4.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
    -- Optional for enhanced UI
    "folke/snacks.nvim",
  },
  config = function()
    require("gdunit4").setup({
      -- Configuration options (see below)
    })
  end,
}
Using packer.nvim
lua
```
# Configuration

The plugin comes with sensible defaults, but you can customize it with the following options:

## Basic Setup

```lua
require("gdunit4").setup({
  -- Your configuration options here
})
```

## Available Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `godot_bin` | string | `os.getenv("GODOT_BIN")` or `"godot-mono"` | Path to Godot executable. Will use the GODOT_BIN environment variable if available. |
| `runner_script` | string | `"addons/gdunit4/runtest.sh"` (Unix) or `"addons/gdunit4/runtest.cmd"` (Windows) | Path to the GdUnit4 test runner script relative to project root. |
| `report_directory` | string | `"reports"` | Directory where test reports will be saved. |
| `report_count` | number | `20` | Number of report folders to keep. Set to 0 to keep all reports. |
| `continue_on_failure` | boolean | `false` | Whether to continue running tests after a failure. |
| `test_config_file` | string | `"GdUnitRunner.cfg"` | Default configuration file for running tests. |
| `ignored_tests` | table | `{}` | List of tests to ignore when running. |
| `debug_mode` | boolean | `true` | Enable detailed logging for debugging. |
| `path_separator` | string | `"/"` (Unix) or `"\\"` (Windows) | Path separator for file paths. Usually auto-detected. |
| `window_position` | string | `"bottom_right"` | Position for test result windows when using snacks.nvim. Options: `"top"`, `"right"`, `"bottom"`, `"left"`, `"center"`, `"float"`, `"bottom_right"`, etc. |
| `use_snacks` | boolean | `true` | Whether to use snacks.nvim for displaying test results (if available). |

## Example Configuration

```lua
require("gdunit4").setup({
  godot_bin = "/usr/local/bin/godot4",
  report_directory = "test-reports",
  report_count = 10,
  debug_mode = false,
  window_position = "bottom",
  use_snacks = true
})
```

You can change these options at any time using the `:GdUnit show_config` command.

## Usage
### Commands
```
:GdUnit run - Run tests for the current file
:GdUnit runAll - Run all tests in the project
:GdUnit runWithConfig [file] - Run tests with a specific config file
:GdUnit create - Generate a test file for the current C# class
:GdUnit open - Open the latest test report
:GdUnit reload - Reload the plugin (useful during development)
:GdUnit debug - Toggle debug mode
:GdUnit show_config - Display current configuration
```
### Creating Tests

1. Open a C# class file in your Godot project
2. Run :GdUnit create
3. The plugin will generate a test file in the test directory
4. Open the generated test file to customize it

### Running Tests

1. Open a test file
2. Run :GdUnit run to execute the current test
3. Results will be displayed in a floating window
4. Use :GdUnit runAll to run all tests in your project

### Test Results

Test results are displayed in a floating window with syntax highlighting:

    ✓ Passed tests are highlighted in green
    ✗ Failed tests are highlighted in red
    Detailed error information is shown for failed tests

If you have snacks.nvim installed, the results window will use its enhanced UI.
Development
Running Tests

This plugin includes tests written using Busted:

```bash

# Run all tests
make test

# Run a specific test file
make test-specific TEST=cmd_utils_spec.lua

# Clean test artifacts
make clean
```
See the tests/README.md file for more information on testing.
License

MIT License
Acknowledgements

    GdUnit4 - The Godot testing framework this plugin integrates with
    plenary.nvim - Library used for utilities
    nvim-treesitter - Used for parsing C# and XML

⚠️ Note: This plugin is still a work in progress. Features may change or break between versions.
