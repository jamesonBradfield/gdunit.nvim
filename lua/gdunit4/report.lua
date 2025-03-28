-- report.lua - Test report handling for GdUnit4
-- Handles parsing XML reports and displaying results

local M = {}

-- Default config for report module
local config = {
  use_snacks = true,
  window_position = 'bottom_right',
}

-- Function to update config
function M.setup(opts)
  if opts then
    for k, v in pairs(opts) do
      config[k] = v
    end
  end
  return M
end

-- Find the most recent report folder
local function find_latest_report(project_root, report_dir)
  local reports_path = project_root .. '/' .. report_dir
  local report_folders = {}

  -- Read the reports directory
  local handle = vim.uv.fs_scandir(reports_path)
  if not handle then
    vim.notify('Failed to read reports directory', vim.log.levels.ERROR)
    return nil
  end

  -- Collect report folders
  while true do
    local name, type = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end

    if type == 'directory' and name:match '^report_%d+$' then
      local num = tonumber(name:match 'report_(%d+)')
      if num then
        table.insert(report_folders, { folder = name, num = num })
      end
    end
  end

  -- Sort and return the latest
  if #report_folders > 0 then
    table.sort(report_folders, function(a, b)
      return a.num > b.num
    end)
    return reports_path .. '/' .. report_folders[1].folder .. '/results.xml'
  end

  -- Fallback to direct results.xml
  local fallback = reports_path .. '/results.xml'
  if vim.uv.fs_stat(fallback) then
    return fallback
  end

  return nil
end

-- Parse XML attributes from node
local function get_node_attr(node, attr_name, buf)
  -- Helper function to extract attribute value from XML node
  -- Simplified version that uses pattern matching instead of complex traversal

  local node_text = vim.treesitter.get_node_text(node, buf)
  local pattern = attr_name .. '="([^"]*)"'
  return node_text:match(pattern)
end

-- Parse test results from XML report
function M.parse_report(project_root, report_dir)
  local report_path = find_latest_report(project_root, report_dir)
  -- check if report exists.
  if not report_path then
    vim.notify('No test report found', vim.log.levels.WARN)
    return nil
  end

  -- Read XML content
  local file = io.open(report_path, 'r')
  if not file then
    return nil
  end
  local xml_content = file:read '*all'
  file:close()

  -- Create buffer with XML content for TreeSitter
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(xml_content, '\n'))

  -- Check for XML parser
  if not vim.treesitter.language.require_language('xml', nil, true) then
    vim.notify('XML parser not available', vim.log.levels.ERROR)
    vim.api.nvim_buf_delete(buf, { force = true })
    return nil
  end

  -- Parse XML with TreeSitter
  local language_tree = vim.treesitter.get_parser(buf, 'xml')
  local syntax_tree = language_tree:parse()
  local root = syntax_tree[1]:root()

  -- Query for test elements
  local query = vim.treesitter.query.parse(
    'xml',
    [[
    (element) @element
  ]]
  )
  -- Process results
  local test_results = {}
  for id, node in query:iter_captures(root, buf) do
    local node_text = vim.treesitter.get_node_text(node, buf)

    -- Check if this is a testsuite element (not testsuites)
    if node_text:match '^%s*<testsuite%s' or node_text:match '^%s*<testsuite>' then
      local suite_name = get_node_attr(node, 'name', buf)
      local suite_time = get_node_attr(node, 'time', buf)

      if suite_name then
        local suite = {
          name = suite_name,
          tests = {},
          time = tonumber(suite_time) or 0,
        }
        test_results[suite_name] = suite

        -- Extract testcase nodes (simplified approach)
        for testcase in node_text:gmatch '<testcase[^>]+>.-</testcase>' do
          local tc_name = testcase:match 'name="([^"]*)"'
          local tc_time = testcase:match 'time="([^"]*)"'
          local has_failure = testcase:match '<failure' or testcase:match '<error'

          -- Extract failure information from CDATA if present
          local failure_info = nil
          if has_failure then
            -- First try to get the message attribute
            local message = testcase:match 'failure%s+message="([^"]*)"'

            -- Extract CDATA content by finding start and end markers directly
            local cdata_start = testcase:find '<!%[CDATA%['
            local cdata_end = testcase:find('%]%]>', cdata_start and (cdata_start + 9) or 1)

            local cdata_content = nil
            if cdata_start and cdata_end then
              cdata_content = testcase:sub(cdata_start + 9, cdata_end - 1)
              -- Trim leading and trailing whitespace including newlines
              cdata_content = cdata_content:match '^%s*(.-)%s*$'
            end

            -- Build the complete failure info
            if message then
              failure_info = message
            end

            if cdata_content and cdata_content:match '%S' then
              -- If we already have message, add the CDATA as additional info
              if failure_info then
                failure_info = failure_info .. '\n' .. cdata_content
              else
                failure_info = cdata_content
              end
            end
          end

          if tc_name then
            table.insert(suite.tests, {
              name = tc_name,
              status = has_failure and 'FAILED' or 'PASSED',
              time = tonumber(tc_time) or 0,
              failure_info = failure_info,
            })
          end
        end
      end
    end
  end

  vim.api.nvim_buf_delete(buf, { force = true })
  return test_results
end

-- Format test results for display
function M.format_results(test_results)
  local lines = {}
  local highlights = {}
  local line_idx = 0
  local total_passed = 0
  local total_failed = 0
  local total_time = 0
  local failure_details = {} -- To collect failure details for summary

  -- Add line with highlight
  local function add_line(text, hl_group)
    table.insert(lines, text)
    if hl_group then
      table.insert(highlights, { line = line_idx, col_start = 0, col_end = -1, hl_group = 'GdUnit4' .. hl_group })
    end
    line_idx = line_idx + 1
  end

  add_line('Test Results', 'Header')
  add_line(string.rep('═', 50))

  -- Sort suites for consistent display
  local sorted_suites = {}
  for suite_name, suite_data in pairs(test_results) do
    table.insert(sorted_suites, { name = suite_name, data = suite_data })
  end
  table.sort(sorted_suites, function(a, b)
    return a.name < b.name
  end)

  for _, suite in ipairs(sorted_suites) do
    add_line(suite.name, 'File')

    -- Sort tests by name for consistent display
    table.sort(suite.data.tests, function(a, b)
      return a.name < b.name
    end)

    -- Display tests
    for _, test in ipairs(suite.data.tests) do
      local symbol = test.status == 'PASSED' and '✓' or '✗'
      local hl = test.status == 'PASSED' and 'TestPassed' or 'TestFailed'

      -- Format the line
      local line = string.format('  %s %s (%dms)', symbol, test.name, math.floor(test.time * 1000))
      add_line(line)

      -- Apply highlight only to the test name portion
      local name_start = line:find(test.name)
      if name_start then
        table.insert(highlights, {
          line = line_idx - 1,
          col_start = name_start - 1,
          col_end = name_start + test.name:len() - 1,
          hl_group = 'GdUnit4' .. hl,
        })
      end

      -- Track totals
      if test.status == 'PASSED' then
        total_passed = total_passed + 1
      else
        total_failed = total_failed + 1

        -- Collect failure details for summary
        if test.failure_info then
          table.insert(failure_details, {
            test = test.name,
            suite = suite.name,
            info = test.failure_info,
          })
        end
      end

      total_time = total_time + test.time
    end

    add_line ''
  end

  add_line(string.rep('─', 50))
  add_line(string.format('Total: %d passed, %d failed', total_passed, total_failed), 'Summary')
  add_line(string.format('Time: %dms', math.floor(total_time * 1000)), 'Time')

  -- Add failure summary section if there are failures
  if #failure_details > 0 then
    add_line ''
    add_line('Failure Details:', 'FailureHeader')
    add_line(string.rep('─', 50))

    for i, failure in ipairs(failure_details) do
      -- First line: test name and suite
      add_line(string.format('%d) %s::%s', i, failure.suite, failure.test), 'TestFailed')

      -- Split the failure info into lines
      if failure.info then
        local info_lines = {}
        for line in failure.info:gmatch '[^\r\n]+' do
          table.insert(info_lines, line)
        end

        -- First line often contains the file:line info
        if #info_lines > 0 and info_lines[1]:match 'FAILED:' then
          add_line(string.format('   %s', info_lines[1]), 'FailureInfo')

          -- Remaining lines are the actual error message
          for j = 2, #info_lines do
            if info_lines[j]:match '%S' then -- Only show non-empty lines
              add_line(string.format('   Error: %s', info_lines[j]), 'FailureInfo')
            end
          end
        else
          -- If we don't have the expected format, just show all lines
          for _, line in ipairs(info_lines) do
            if line:match '%S' then -- Only show non-empty lines
              add_line(string.format('   %s', line), 'FailureInfo')
            end
          end
        end
      end

      add_line ''
    end
  end

  return lines, highlights
end

-- Modified display_results function with better snacks.nvim detection
function M.display_results(project_root, report_dir, position)
  -- Parse the report
  local test_results = M.parse_report(project_root, report_dir)
  if not test_results or vim.tbl_isempty(test_results) then
    vim.notify('No test results to display', vim.log.levels.WARN)
    return
  end

  -- Format the results
  local lines, highlights = M.format_results(test_results)

  -- Improved snacks.nvim detection
  local has_snacks = false
  local Snacks = nil

  -- Try to get the snacks module
  local status, snacks_module = pcall(require, 'snacks')
  if status then
    -- Check if the global Snacks variable exists
    if _G.Snacks ~= nil then
      has_snacks = true
      Snacks = _G.Snacks
    end
  end

  if has_snacks and Snacks and Snacks.win and type(Snacks.win) == 'function' and config.use_snacks then
    vim.notify('Using snacks.nvim for display', vim.log.levels.DEBUG)

    -- Try to create a window using snacks.win
    local success, win_or_error = pcall(function()
      return Snacks.win {
        title = 'GdUnit4 Test Results',
        position = position or 'float', -- Use provided position or default to float
        width = 0.8, -- 80% of screen width
        height = 0.8, -- 80% of screen height
        border = 'rounded',
        text = lines,
        keys = {
          q = 'close',
          ['<Esc>'] = 'close',
        },
        on_win = function(self)
          -- Apply highlights with better error handling
          local ns_id = vim.api.nvim_create_namespace 'gdunit4_results'
          for _, hl in ipairs(highlights) do
            pcall(function()
              vim.api.nvim_buf_add_highlight(self.buf, ns_id, hl.hl_group, hl.line, hl.col_start, hl.col_end)
            end)
          end
        end,
      }
    end)

    if success then
      return win_or_error
    else
      vim.notify('Failed to create window with snacks.nvim: ' .. tostring(win_or_error), vim.log.levels.WARN)
      -- Fall through to the native implementation
    end
  else
    if config.use_snacks then
      vim.notify('snacks.nvim not available, falling back to native window', vim.log.levels.DEBUG)
    end
  end

  -- Fall back to native Neovim floating window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Apply highlights with better error handling
  local ns_id = vim.api.nvim_create_namespace 'gdunit4_results'
  for _, hl in ipairs(highlights) do
    pcall(function()
      vim.api.nvim_buf_add_highlight(buf, ns_id, hl.hl_group, hl.line, hl.col_start, hl.col_end)
    end)
  end

  -- Display in floating window
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

-- Debug the snacks.nvim integration
function M.debug_snacks()
  local info = {
    snacks_required = false,
    global_snacks = false,
    win_function = false,
    config = vim.inspect(config),
  }

  -- Check if we can require snacks
  local status, _ = pcall(require, 'snacks')
  info.snacks_required = status

  -- Check if global Snacks exists
  info.global_snacks = _G.Snacks ~= nil

  -- Check if win function exists
  if info.global_snacks then
    info.win_function = type(_G.Snacks.win) == 'function'
  end

  -- Create a buffer with the debug info
  local buf = vim.api.nvim_create_buf(false, true)

  -- Format the info as lines
  local lines = {
    'GdUnit4 snacks.nvim Debug Info:',
    '-------------------------',
    'snacks module loaded: ' .. tostring(info.snacks_required),
    'global Snacks exists: ' .. tostring(info.global_snacks),
    'Snacks.win is a function: ' .. tostring(info.win_function),
    'Configuration:',
    info.config,
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

  return {
    info = info,
    win = win,
    buf = buf,
  }
end

-- Clean old reports
function M.clean_old_reports(project_root, report_dir, max_reports)
  if not max_reports or max_reports <= 0 then
    return
  end

  local full_report_path = project_root .. '/' .. report_dir
  local handle = vim.uv.fs_scandir(full_report_path)
  if not handle then
    return
  end

  local reports = {}
  while true do
    local name, type = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end

    if type == 'directory' and name:match '^report_%d+$' then
      local num = tonumber(name:match 'report_(%d+)')
      if num then
        table.insert(reports, { name = name, num = num })
      end
    end
  end

  -- Sort reports by number (latest first)
  table.sort(reports, function(a, b)
    return a.num > b.num
  end)

  -- Remove excess reports
  if #reports > max_reports then
    for i = max_reports + 1, #reports do
      local path = full_report_path .. '/' .. reports[i].name
      vim.fn.delete(path, 'rf')
    end
  end
end

return M
