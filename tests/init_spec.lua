-- Create this file as tests/init_spec.lua
local helper = require("test_helper")

describe("init", function()
  local gdunit4
  local cmd_utils
  local report

  before_each(function()
    helper.reset_notifications()
    helper.reset_mocks()
    
    -- Load dependencies first with mocks
    cmd_utils = require("gdunit4.cmd_utils")
    cmd_utils.setup = function() return cmd_utils end
    cmd_utils.log = function() end
    
    report = require("gdunit4.report")
    report.setup = function() return report end
    report.clean_old_reports = function() end
    report.display_results = function() return true end
    
    -- Then load the init module
    gdunit4 = require("gdunit4")
  end)

  after_each(function()
    package.loaded["gdunit4"] = nil
    package.loaded["gdunit4.cmd_utils"] = nil
    package.loaded["gdunit4.report"] = nil
  end)

  describe("setup", function()
    it("should apply configuration", function()
      -- Mock api functions
      local commands_created = {}
      vim.api.nvim_create_user_command = function(name, callback, opts)
        table.insert(commands_created, name)
      end
      
      local highlights_set = {}
      vim.api.nvim_set_hl = function(ns, name, opts)
        table.insert(highlights_set, name)
      end
      
      -- Run setup
      gdunit4.setup({ debug_mode = true, window_position = "top" })
      
      -- Verify commands were created
      assert.is_true(#commands_created > 0)
      assert.is_true(vim.tbl_contains(commands_created, "GdUnit"))
      assert.is_true(vim.tbl_contains(commands_created, "GdUnitDebugSnacks"))
      
      -- Verify highlights were set
      assert.is_true(#highlights_set > 0)
      assert.is_true(vim.tbl_contains(highlights_set, "GdUnit4TestPassed"))
      assert.is_true(vim.tbl_contains(highlights_set, "GdUnit4TestFailed"))
    end)
  end)

  describe("find_project_root", function()
    it("should find project root with project.godot", function()
      -- Mock file existence
      vim.fn.filereadable = function(path)
        return path:match("project%.godot$") and 1 or 0
      end
      
      -- Mock expand for current file
      vim.fn.expand = function(expr)
        return "/path/to/file"
      end
      
      -- Mock fnamemodify to simulate going up directories
      local call_count = 0
      vim.fn.fnamemodify = function(path, modifier)
        call_count = call_count + 1
        if call_count == 1 then
          return "/path/to"
        elseif call_count == 2 then
          return "/path"
        else
          return "/"
        end
      end
      
      local root = gdunit4.find_project_root()
      assert.equals("/path/to", root)
    end)
    
    it("should return nil if project.godot not found", function()
      -- Mock file existence to always fail
      vim.fn.filereadable = function(path)
        return 0
      end
      
      -- Mock expand for current file
      vim.fn.expand = function(expr)
        return "/path/to/file"
      end
      
      -- Mock fnamemodify to simulate going up directories
      local dirs = { "/path/to", "/path", "/" }
      local call_count = 0
      vim.fn.fnamemodify = function(path, modifier)
        call_count = call_count + 1
        if call_count <= #dirs then
          return dirs[call_count]
        else
          return "/"
        end
      end
      
      -- Mock getcwd
      vim.fn.getcwd = function()
        return "/cwd"
      end
      
      local root = gdunit4.find_project_root()
      assert.is_nil(root)
    end)
  end)

  describe("with_project_dir", function()
    it("should execute callback in project context", function()
      -- Mock find_project_root
      gdunit4.find_project_root = function()
        return "/project/root"
      end
      
      -- Mock chdir
      local chdir_calls = {}
      vim.fn.chdir = function(dir)
        table.insert(chdir_calls, dir)
      end
      
      -- Mock getcwd
      vim.fn.getcwd = function()
        return "/original/dir"
      end
      
      -- Mock mkdir
      local mkdir_calls = {}
      vim.fn.mkdir = function(dir, mode)
        table.insert(mkdir_calls, { dir = dir, mode = mode })
        return 0
      end
      
      -- Execute with callback
      local callback_executed = false
      local callback_arg = nil
      gdunit4.with_project_dir(function(arg)
        callback_executed = true
        callback_arg = arg
        return "callback result"
      end)
      
      -- Verify callback execution
      assert.is_true(callback_executed)
      assert.equals("/project/root", callback_arg)
      
      -- Verify directory changes
      assert.equals(2, #chdir_calls)
      assert.equals("/project/root", chdir_calls[1])
      assert.equals("/original/dir", chdir_calls[2])
      
      -- Verify reports directory creation
      assert.equals(1, #mkdir_calls)
      assert.truthy(mkdir_calls[1].dir:match("reports"))
    end)
  end)

  describe("build_command", function()
    it("should build command with test path", function()
      -- Set config values
      gdunit4.setup({
        runner_script = "addons/gdunit4/runtest.sh",
        report_directory = "reports",
        report_count = 10
      })
      
      -- Mock escape_path
      cmd_utils.escape_path = function(path)
        return path
      end
      
      -- Test specific file
      vim.fn.filereadable = function(path)
        return path:match("%.cs$") and 1 or 0
      end
      
      vim.fn.fnamemodify = function(path, modifier)
        return "TestFile.cs"
      end
      
      local cmd = gdunit4.build_command("/path/to/TestFile.cs")
      assert.truthy(cmd:match("^addons/gdunit4/runtest.sh"))
      assert.truthy(cmd:match("-a test/TestFile.cs"))
      assert.truthy(cmd:match("-rd reports"))
      assert.truthy(cmd:match("-rc 10"))
    end)
    
    it("should build command with config file", function()
      -- Set config values
      gdunit4.setup({
        runner_script = "addons/gdunit4/runtest.sh",
        report_directory = "reports",
        report_count = 10
      })
      
      -- Mock escape_path
      cmd_utils.escape_path = function(path)
        return path
      end
      
      local cmd = gdunit4.build_command(nil, { config = "test_config.cfg" })
      assert.truthy(cmd:match("^addons/gdunit4/runtest.sh"))
      assert.truthy(cmd:match("-conf test_config.cfg"))
      assert.truthy(cmd:match("-rd reports"))
      assert.truthy(cmd:match("-rc 10"))
    end)
  end)

  describe("run_test", function()
    it("should run test for current file", function()
      -- Mock with_project_dir to execute callback
      gdunit4.with_project_dir = function(callback)
        return callback()
      end
      
      -- Mock with_project_verification to do nothing
      gdunit4.with_project_verification = function() end
      
      -- Mock expand for current file
      vim.fn.expand = function(expr)
        return "/path/to/TestFile.cs"
      end
      
      -- Mock build_command
      gdunit4.build_command = function(path, opts)
        assert.equals("/path/to/TestFile.cs", path)
        return "test_command"
      end
      
      -- Mock execute_sync
      cmd_utils.execute_sync = function(cmd, opts)
        assert.equals("test_command", cmd)
        if opts and opts.callback then opts.callback() end
        return "output", 0
      end
      
      local result = gdunit4.run_test()
      assert.is_true(result)
    end)
  end)
end)
