-- Create this file as tests/test_helper.lua

-- This file is loaded before each test file
-- Set up common test helpers and utilities here

-- Record notifications for assertion
local notifications = {}

-- Override vim.notify to capture notifications during tests
local real_notify = vim.notify
vim.notify = function(msg, level, opts)
  table.insert(notifications, {
    msg = msg,
    level = level or vim.log.levels.INFO,
    opts = opts or {}
  })
  -- Uncomment to see notifications during tests
  -- real_notify(msg, level, opts)
end

-- Helper to reset notifications
local function reset_notifications()
  notifications = {}
end

-- Helper to get captured notifications
local function get_notifications()
  return notifications
end

-- Mock file system operations
local real_fs = vim.uv.fs_stat
local mock_files = {}

-- Helper to mock files for testing
local function mock_file(path, exists, stat_data)
  mock_files[path] = {
    exists = exists,
    stat = stat_data or {
      type = "file",
      mode = 0x1A4, -- 0644
      size = 1024,
      atime = {sec = 0, nsec = 0},
      mtime = {sec = 0, nsec = 0},
      ctime = {sec = 0, nsec = 0}
    }
  }
end

-- Override fs_stat for testing
vim.uv.fs_stat = function(path)
  if mock_files[path] then
    if mock_files[path].exists then
      return mock_files[path].stat
    else
      return nil
    end
  end
  -- Fall back to real fs_stat if not mocked
  return real_fs(path)
end

-- Reset mocks
local function reset_mocks()
  mock_files = {}
end

-- Restore real functions
local function restore_real_functions()
  vim.notify = real_notify
  vim.uv.fs_stat = real_fs
end

-- Create a simple table stub for testing
local function stub_table(tbl, field, return_value)
  local old_value = tbl[field]
  tbl[field] = function()
    return return_value
  end
  return function()
    tbl[field] = old_value
  end
end

-- Export all helper functions
return {
  reset_notifications = reset_notifications,
  get_notifications = get_notifications,
  mock_file = mock_file,
  reset_mocks = reset_mocks,
  restore_real_functions = restore_real_functions,
  stub_table = stub_table
}
