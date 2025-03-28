-- Create this file as tests/cmd_utils_spec.lua
local helper = require 'test_helper'

describe('cmd_utils', function()
  local cmd_utils

  before_each(function()
    helper.reset_notifications()
    helper.reset_mocks()
    cmd_utils = require 'gdunit4.cmd_utils'
    cmd_utils.setup { notify_commands = true, notify_level = vim.log.levels.INFO }
  end)

  after_each(function()
    package.loaded['gdunit4.cmd_utils'] = nil
  end)

  describe('setup', function()
    it('should apply configuration', function()
      cmd_utils.setup { notify_commands = false }
      cmd_utils.log 'Test message'
      local notifications = helper.get_notifications()
      assert.equals(0, #notifications)
    end)
  end)

  describe('log', function()
    it('should log messages with proper level', function()
      cmd_utils.log 'Info message'
      cmd_utils.log('Error message', vim.log.levels.ERROR)

      local notifications = helper.get_notifications()
      assert.equals(2, #notifications)
      assert.equals('Info message', notifications[1].msg)
      assert.equals(vim.log.levels.INFO, notifications[1].level)
      assert.equals('Error message', notifications[2].msg)
      assert.equals(vim.log.levels.ERROR, notifications[2].level)
    end)
  end)

  describe('escape_path', function()
    it('should escape spaces on Unix', function()
      -- Mock platform to Unix
      local restore = helper.stub_table(vim.fn, 'has', 0)

      local path = 'path with spaces'
      local escaped = cmd_utils.escape_path(path)
      assert.equals('path\\ with\\ spaces', escaped)

      restore()
    end)

    it('should quote paths with spaces on Windows', function()
      -- Mock platform to Windows
      local restore = helper.stub_table(vim.fn, 'has', 1)

      local path = 'path with spaces'
      local escaped = cmd_utils.escape_path(path)
      assert.equals('"path with spaces"', escaped)

      restore()
    end)
  end)

  describe('build_command', function()
    it('should build command with arguments', function()
      local base = 'base_cmd'
      local args = { '-a', '--flag', 'file name' }

      -- Mock platform to Unix
      local restore = helper.stub_table(vim.fn, 'has', 0)

      local cmd = cmd_utils.build_command(base, args)
      assert.equals('base_cmd -a --flag file\\ name', cmd)

      restore()
    end)
  end)

  describe('execute_sync', function()
    it('should execute command and return result', function()
      -- This test is tricky as it relies on system commands
      -- Here we'll just verify the function doesn't crash

      -- Mock system and v.shell_error
      local old_system = vim.fn.system
      local old_shell_error = vim.v.shell_error

      vim.fn.system = function(cmd)
        return 'mocked output'
      end
      vim.v.shell_error = 0

      local output, exit_code = cmd_utils.execute_sync 'echo test'

      assert.equals('mocked output', output)
      assert.equals(0, exit_code)

      -- Restore
      vim.fn.system = old_system
      vim.v.shell_error = old_shell_error
    end)
  end)

  describe('is_program_available', function()
    it('should check if program is available', function()
      -- Mock os.execute to control the return value
      local old_execute = os.execute

      -- Program exists
      os.execute = function()
        return 0
      end
      assert.is_true(cmd_utils.is_program_available 'existing_program')

      -- Program doesn't exist
      os.execute = function()
        return 1
      end
      assert.is_false(cmd_utils.is_program_available 'non_existing_program')

      -- Restore
      os.execute = old_execute
    end)
  end)
end)
