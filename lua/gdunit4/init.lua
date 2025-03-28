-- GdUnit4 plugin for Neovim

local M = {}
local cmd_utils = require 'gdunit4.cmd_utils'
local parser = require 'gdunit4.parser'
local generator = require 'gdunit4.generator'
local report = require 'gdunit4.report'
local project_root
local original_dir
local DEFAULT_CONFIG = {
  godot_bin = os.getenv 'GODOT_BIN' or 'godot-mono',
  runner_script = vim.fn.has 'win32' == 1 and 'addons/gdUnit4/runtest.cmd' or 'addons/gdUnit4/runtest.sh',
  report_directory = 'reports',
  report_count = 20,
  continue_on_failure = false,
  test_config_file = 'GdUnitRunner.cfg',
  ignored_tests = {},
  path_separator = vim.fn.has 'win32' == 1 and '\\' or '/',
  debug_mode = true,
  window_position = 'bottom_right', -- Default window position for snacks.nvim
  use_snacks = true, -- Whether to use snacks.nvim for windows
}

local config = vim.deepcopy(DEFAULT_CONFIG) -- This just copies a table with functions intact.
---Helper function to reload the plugin
function M.reload()
  -- Clear the cache for all gdunit4 modules
  for module_name, _ in pairs(package.loaded) do
    if module_name:match '^gdunit4' then
      package.loaded[module_name] = nil
    end
  end

  -- Re-require the main module and setup
  local gdunit4 = require 'gdunit4'
  gdunit4.setup() -- Pass your config if needed

  vim.notify('GdUnit4 plugin reloaded', vim.log.levels.INFO)
end

---Setup GdUnit4 with optional configuration
---@param opts table|nil Configuration options
function M.setup(opts)
  -- Merge user config with defaults
  if opts then
    for k, v in pairs(opts) do
      config[k] = v
    end
  end

  -- Set up cmd_utils
  cmd_utils.setup {
    notify_commands = true,
    notify_level = config.debug_mode and vim.log.levels.DEBUG or vim.log.levels.INFO,
  }

  -- Share relevant config with report module
  report.setup {
    use_snacks = config.use_snacks,
    window_position = config.window_position,
  }

  -- Register commands
  vim.api.nvim_create_user_command('GdUnit', function(args)
    local subcmd = args.args

    if subcmd == 'run' then
      M.run_test()
    elseif subcmd == 'runAll' then
      M.run_all_tests()
    elseif subcmd:match '^runWithConfig' then
      -- Extract the config file if provided after the subcommand
      local config_file = subcmd:match '^runWithConfig%s+(.+)$'
      M.run_with_config(config_file)
    elseif subcmd == 'create' then
      M.create_test()
    elseif subcmd == 'open' then
      M.open_latest_report()
    elseif subcmd == 'reload' then
      M.reload()
    elseif subcmd == 'debug' then
      M.toggle_debug_mode()
    elseif subcmd == 'show_config' then
      M.print_config()
    else
      cmd_utils.log('Unknown GdUnit subcommand: ' .. subcmd, vim.log.levels.ERROR)
    end
  end, {
    nargs = '+',
    ---@diagnostic disable-next-line: unused-local
    complete = function(ArgLead, CmdLine, CursorPos)
      local sub_cmds = { 'run', 'runAll', 'runWithConfig', 'create', 'open', 'reload' }
      local args = vim.split(CmdLine, '%s+')

      -- If we're completing the subcommand
      if #args <= 2 then
        return vim.tbl_filter(function(cmd)
          return cmd:match('^' .. ArgLead)
        end, sub_cmds)
        -- If we're completing runWithConfig args
      elseif args[2] == 'runWithConfig' then
        return vim.fn.glob('*.cfg', false, true)
      end

      return {}
    end,
  })

  -- Add debug command for snacks integration
  vim.api.nvim_create_user_command('GdUnitDebugSnacks', function()
    report.debug_snacks()
  end, {})

  -- Initialize highlights
  M._init_highlights()
end

function M._init_highlights()
  -- Setup highlight groups for test results
  local highlights = {
    TestPassed = { fg = '#00ff00', bold = true },
    TestFailed = { fg = '#ff0000', bold = true },
    FailureHeader = { fg = '#ff8800', italic = true },
    FailureInfo = { fg = '#ff8800' },
    Header = { fg = '#7aa2f7', bold = true },
    Summary = { fg = '#9ece6a' },
    File = { fg = '#ffffff', bold = true },
    FuncName = { fg = '#cccccc' },
    Time = { fg = '#cccccc', italic = true },
  }

  for name, settings in pairs(highlights) do
    vim.api.nvim_set_hl(0, 'GdUnit4' .. name, settings)
  end
end

--- get project root
---@param start_dir string|nil Optional directory to start searching from
---@return string|nil Path to project root or nil if not found
function M.find_project_root(start_dir)
  -- Try current file's directory first
  if not start_dir or start_dir == '' then
    local current_file = vim.fn.expand '%:p:h'
    if current_file and current_file ~= '' then
      start_dir = current_file
    else
      -- Fall back to current working directory
      start_dir = vim.fn.getcwd()
    end
  end

  -- Navigate up through directories looking for project.godot
  local current_dir = start_dir
  local last_dir = nil

  while current_dir and current_dir ~= '' and current_dir ~= last_dir do
    local project_file = current_dir .. config.path_separator .. 'project.godot'
    if vim.fn.filereadable(project_file) == 1 then
      if config.debug_mode then
        cmd_utils.log('Found project root: ' .. current_dir, vim.log.levels.DEBUG)
      end
      return current_dir
    end

    -- Save current directory before going up
    last_dir = current_dir
    -- Move up one directory
    current_dir = vim.fn.fnamemodify(current_dir, ':h')
  end

  -- Not found in file hierarchy, check current working directory
  local cwd = vim.fn.getcwd()
  local cwd_project_file = cwd .. config.path_separator .. 'project.godot'

  if vim.fn.filereadable(cwd_project_file) == 1 then
    if config.debug_mode then
      cmd_utils.log('Found project root in cwd: ' .. cwd, vim.log.levels.DEBUG)
    end
    return cwd
  end

  -- Not found
  cmd_utils.log('Could not find project.godot file', vim.log.levels.ERROR)
  return nil
end

---Execute a function in the context of the project directory
---@param callback function Function to execute
---@return any Result of callback or nil on error
function M.with_project_dir(callback)
  project_root = M.find_project_root()
  if not project_root then
    return nil
  end
  -- Store current directory
  original_dir = vim.fn.getcwd()
  local success, result = nil, nil

  -- Change to project directory
  local ok = pcall(vim.fn.chdir, project_root)
  if not ok then
    cmd_utils.log('Failed to change directory to: ' .. project_root, vim.log.levels.ERROR)
    return nil
  end
  -- Create reports directory if it doesn't exist
  local report_dir = project_root .. config.path_separator .. config.report_directory
  vim.fn.mkdir(report_dir, 'p')

  -- Clean old reports if needed using report.lua function
  if config.report_count and config.report_count > 0 then
    report.clean_old_reports(project_root, config.report_directory, config.report_count)
  end

  -- Execute callback in project context
  success, result = pcall(callback, project_root)

  -- Restore original directory
  vim.fn.chdir(original_dir)

  if not success then
    cmd_utils.log('Error in callback: ' .. tostring(result), vim.log.levels.ERROR)
    return nil
  end

  return result
end

---Verify we have a valid godot project
---@return nil
function M.with_project_verification()
  -- this should be a seperate verification (whether its in our other one or seperate)
  local godot_bin = config.godot_bin
  if godot_bin == '' then
    cmd_utils.log('Godot binary not set', vim.log.levels.ERROR)
    return nil
  end

  -- Verify the godot binary exists
  if vim.fn.executable(godot_bin) ~= 1 then
    cmd_utils.log('Godot executable not found: ' .. godot_bin, vim.log.levels.ERROR)
    return nil
  end
  -- Check runner script
  local runner_script = project_root .. config.path_separator .. config.runner_script
  if vim.fn.has 'unix' == 1 then
    local script_stat = vim.uv.fs_stat(runner_script)

    if not script_stat then
      cmd_utils.log('Runner script not found at: ' .. runner_script, vim.log.levels.ERROR)
      vim.fn.chdir(original_dir)
      return nil
    end

    -- Check if script is executable
    local executable_bit = 64 -- equivalent to 0x40
    if bit.band(script_stat.mode, executable_bit) == 0 then
      cmd_utils.log('Setting executable permissions on runner script', vim.log.levels.INFO)

      local chmod_ok = pcall(vim.uv.fs_chmod, runner_script, 493) -- 0755
      if not chmod_ok then
        cmd_utils.log('Failed to set permissions on runner script', vim.log.levels.ERROR)
        vim.fn.chdir(original_dir)
        return nil
      end
    end
  end
end

---Get path relative to project root
---@param full_path string Absolute path
---@param add_leading_slash boolean|nil Whether to add leading slash
---@return string Relative path
function M.get_relative_path(full_path, add_leading_slash)
  -- Ensure consistent forward slashes
  full_path = full_path:gsub('\\', '/')

  -- Replace backslashes with forward slashes for consistency
  project_root = project_root:gsub('\\', '/')

  -- For GdUnit4, we need to consider two path formats:
  -- 1. Absolute path format: /project_name/path/to/file
  -- 2. Relative path format: path/to/file (relative to project root)

  -- Check if the path is already within the project root
  if full_path:find(project_root, 1, true) == 1 then
    -- Path is within project root, so make it relative to project root
    local rel_path = full_path:sub(#project_root + 2) -- +2 to remove the trailing slash

    if add_leading_slash then
      -- For GdUnit4, this should be: /project_name/rel_path
      local project_name = vim.fn.fnamemodify(project_root, ':t')
      return '/' .. project_name .. '/' .. rel_path
    else
      -- Just return the relative path
      return rel_path
    end
  else
    -- Path is not within project root
    cmd_utils.log('Warning: Path not within project root: ' .. full_path, vim.log.levels.WARN)

    -- If add_leading_slash is true, we should still try to format as GdUnit4 expects
    if add_leading_slash then
      local project_name = vim.fn.fnamemodify(project_root, ':t')
      return '/' .. project_name .. '/' .. vim.fn.fnamemodify(full_path, ':t')
    else
      return full_path
    end
  end
end

function M.build_command(test_path, options)
  options = options or {}
  local runner_script = config.runner_script:gsub('^/', '')

  -- Build command
  local cmd = runner_script

  -- Add test path or config
  if test_path then
    -- ULTRA SIMPLE PATH HANDLING - just use "test" for everything
    local simple_path = 'test'

    -- Only extract specific test file if needed (uses more robust pattern matching)
    if vim.fn.filereadable(test_path) == 1 and test_path:match '%.cs$' then
      -- For a specific test file, just use the filename without path
      local filename = vim.fn.fnamemodify(test_path, ':t')
      simple_path = 'test/' .. filename
    end

    -- Debug logging
    if config.debug_mode then
      cmd_utils.log('Original test path: ' .. test_path, vim.log.levels.DEBUG)
      cmd_utils.log('Using simplified path: ' .. simple_path, vim.log.levels.DEBUG)
    end

    cmd_utils.log('Running tests on: ' .. simple_path, vim.log.levels.INFO)
    cmd = cmd .. ' -a ' .. cmd_utils.escape_path(simple_path)
  elseif options.config then
    cmd = cmd .. ' -conf ' .. cmd_utils.escape_path(options.config)
  end

  -- Add report arguments
  if config.report_directory then
    cmd = cmd .. ' -rd ' .. cmd_utils.escape_path(config.report_directory:gsub('^/', ''))
  end

  if config.report_count then
    cmd = cmd .. ' -rc ' .. tostring(config.report_count)
  end

  -- Add debug if needed
  if options.debug then
    cmd = cmd .. ' --debug'
  end

  -- Log the complete command for debugging
  if config.debug_mode then
    cmd_utils.log('Final command: ' .. cmd, vim.log.levels.DEBUG)
  end

  return cmd
end

-- ---Run a single test file
-- ---@param opts table|nil Options for test run
-- ---@return boolean Success status
function M.run_test(opts)
  return M.with_project_dir(function()
    M.with_project_verification()
    local current_file = vim.fn.expand '%:p'
    if not current_file or current_file == '' then
      cmd_utils.log('No file selected', vim.log.levels.ERROR)
      return false
    end

    local cmd = M.build_command(current_file, opts)
    return cmd_utils.execute_sync(cmd, {
      callback = function()
        report.display_results(project_root, config.report_directory, config.window_position)
      end,
    }) == 0
  end) or false
end

-- ---Run a all test files
-- ---@return boolean Success status
function M.run_all_tests()
  return M.with_project_dir(function()
    M.with_project_verification()
    local test_path = 'test'

    local cmd = M.build_command(test_path)

    cmd_utils.log('Executing all tests command: ' .. cmd, vim.log.levels.INFO)
    return cmd_utils.execute_sync(cmd, {
      callback = function()
        report.display_results(project_root, config.report_directory, config.window_position)
      end,
    }) == 0
  end) or false
end

--
---Run tests using a configuration file
---@param config_file string|nil Path to config file
---@return boolean Success status
function M.run_with_config(config_file)
  return M.with_project_dir(function()
    M.with_project_verification()
    local cmd = M.build_command(nil, {
      config = config_file or config.test_config_file,
    })
    return cmd_utils.execute_sync(cmd, {
      callback = function()
        report.display_results(project_root, config.report_directory, config.window_position)
      end,
    }) == 0
  end) or false
end

---Create a test file for the current file
---@return boolean Success status
function M.create_test()
  -- Get current file
  local current_file_path = vim.fn.expand '%:p'
  if not current_file_path or current_file_path == '' then
    cmd_utils.log('No file selected', vim.log.levels.ERROR)
    return false
  end

  -- Check if it's a C# file
  if not current_file_path:match '%.cs$' then
    cmd_utils.log('Current file is not a C# file', vim.log.levels.ERROR)
    return false
  end

  -- Parse the file
  local file_data = parser.parse_file(current_file_path)
  if not file_data then
    cmd_utils.log('Failed to parse C# file', vim.log.levels.ERROR)
    return false
  end

  -- Generate test content
  local test_content = generator.generate_test_class(file_data)

  -- Create test file path
  local test_file_name = vim.fn.fnamemodify(current_file_path, ':t:r') .. '_test.cs'
  local test_dir = project_root .. '/test'

  -- Create test directory if it doesn't exist
  vim.fn.mkdir(test_dir, 'p')
  local test_file_path = test_dir .. '/' .. test_file_name

  -- Write the test content to file
  local success = vim.fn.writefile(vim.split(test_content, '\n'), test_file_path) == 0

  if success then
    cmd_utils.log('Test written to: ' .. test_file_path, vim.log.levels.INFO)

    -- Ask if the user wants to open the test file
    if vim.fn.confirm('Open the test file?', '&Yes\n&No', 1) == 1 then
      vim.cmd('edit ' .. vim.fn.fnameescape(test_file_path))
    end

    return true
  else
    cmd_utils.log('Failed to write test file', vim.log.levels.ERROR)
    return false
  end
end

-- Helper function to toggle debug mode
function M.toggle_debug_mode()
  config.debug_mode = not config.debug_mode
  cmd_utils.setup {
    notify_commands = true,
    notify_level = config.debug_mode and vim.log.levels.DEBUG or vim.log.levels.INFO,
  }

  local mode = config.debug_mode and 'enabled' or 'disabled'
  vim.notify('GdUnit4 debug mode ' .. mode, vim.log.levels.INFO)

  return config.debug_mode
end

-- Improved configuration printing for debugging
function M.print_config()
  local config_str = vim.inspect(config)

  -- Create a buffer with the config info
  local buf = vim.api.nvim_create_buf(false, true)

  -- Format the info as lines
  local lines = {
    'GdUnit4 Configuration:',
    '-------------------------',
    config_str,
  }

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Display in a floating window
  local width = math.min(80, vim.o.columns - 4)
  local height = math.min(#lines + 2, vim.o.lines - 4)

  local win_opts = {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
  }

  local win = vim.api.nvim_open_win(buf, true, win_opts)

  -- Set keymaps for closing
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':close<CR>', { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', ':close<CR>', { noremap = true, silent = true })

  return win
end

-- Add a health check module
local health = {}

function health.check()
  if vim.fn.has('nvim-0.8.0') == 0 then
    vim.health.warn("GdUnit4 requires Neovim >= 0.8.0")
  else
    vim.health.ok("Using Neovim >= 0.8.0")
  end
  
  -- Check for godot binary
  if vim.fn.executable(config.godot_bin) == 1 then
    vim.health.ok("Godot binary found: " .. config.godot_bin)
  else
    vim.health.error("Godot binary not found: " .. config.godot_bin)
    vim.health.info("Set 'godot_bin' in your config or set GODOT_BIN environment variable")
  end
  
  -- Check for treesitter XML parser (needed for report parsing)
  local has_xml_parser = pcall(function()
    vim.treesitter.language.require_language('xml', nil, true)
  end)
  
  if has_xml_parser then
    vim.health.ok("Treesitter XML parser found")
  else
    vim.health.warn("Treesitter XML parser not found (needed for report parsing)")
    vim.health.info("Install with ':TSInstall xml'")
  end
  
  -- Check for snacks.nvim integration
  local has_snacks = false
  local snacks_status = "Not available"
  
  -- Try to get the snacks module
  local status, snacks_module = pcall(require, 'snacks')
  if status then
    -- Check if the global Snacks variable exists
    if _G.Snacks ~= nil then
      has_snacks = true
      snacks_status = "Available"
    end
  end
  
  if has_snacks then
    vim.health.ok("snacks.nvim integration: " .. snacks_status)
  else
    if config.use_snacks then
      vim.health.warn("snacks.nvim integration enabled but snacks.nvim not found")
    else
      vim.health.info("snacks.nvim integration disabled")
    end
  end
end

M.health = health

return M
