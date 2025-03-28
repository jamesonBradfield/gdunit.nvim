-- Create this file as tests/report_spec.lua
local helper = require("test_helper")

describe("report", function()
  local report

  before_each(function()
    helper.reset_notifications()
    helper.reset_mocks()
    report = require("gdunit4.report")
    report.setup({ use_snacks = true, window_position = "bottom_right" })
  end)

  after_each(function()
    package.loaded["gdunit4.report"] = nil
  end)

  describe("setup", function()
    it("should apply configuration", function()
      report.setup({ use_snacks = false, window_position = "center" })
      
      -- Access private config via debug_snacks (hacky but works for testing)
      local debug_result = report.debug_snacks()
      local config_string = debug_result.info.config
      
      assert.truthy(config_string:match("use_snacks = false"))
      assert.truthy(config_string:match("window_position = \"center\""))
    end)
  end)

  describe("clean_old_reports", function()
    it("should clean old reports", function()
      local project_root = "/mock/project"
      local report_dir = "reports"
      local max_reports = 2
      
      -- Mock filesystem functions
      local mock_scandir_data = {
        { name = "report_3", type = "directory" },
        { name = "report_1", type = "directory" },
        { name = "report_2", type = "directory" },
        { name = "other_file", type = "file" },
      }
      
      local scandir_idx = 0
      local scandir_handle = {}
      
      -- Mock fs_scandir
      vim.uv.fs_scandir = function()
        return scandir_handle
      end
      
      -- Mock fs_scandir_next
      vim.uv.fs_scandir_next = function()
        scandir_idx = scandir_idx + 1
        if scandir_idx <= #mock_scandir_data then
          return mock_scandir_data[scandir_idx].name, mock_scandir_data[scandir_idx].type
        else
          return nil
        end
      end
      
      -- Mock delete
      local deleted_paths = {}
      vim.fn.delete = function(path, flags)
        table.insert(deleted_paths, { path = path, flags = flags })
        return 0
      end
      
      -- Run the function
      report.clean_old_reports(project_root, report_dir, max_reports)
      
      -- Verify the right ones were deleted (should be report_1 since 3 and 2 are newer)
      assert.equals(1, #deleted_paths)
      assert.equals("/mock/project/reports/report_1", deleted_paths[1].path)
      assert.equals("rf", deleted_paths[1].flags)
    end)
    
    it("should do nothing if max_reports is 0", function()
      -- Mock delete to verify it's not called
      local delete_called = false
      vim.fn.delete = function() delete_called = true; return 0 end
      
      report.clean_old_reports("/path", "reports", 0)
      assert.is_false(delete_called)
    end)
  end)

  describe("format_results", function()
    it("should format test results correctly", function()
      local test_results = {
        TestSuite1 = {
          name = "TestSuite1",
          time = 1.5,
          tests = {
            {
              name = "Test1",
              status = "PASSED",
              time = 0.5,
            },
            {
              name = "Test2",
              status = "FAILED",
              time = 1.0,
              failure_info = "FAILED: /path/to/test.cs:42\nExpected true but got false"
            }
          }
        }
      }
      
      local lines, highlights = report.format_results(test_results)
      
      -- Check if we have the expected lines
      assert.is_true(#lines > 0)
      assert.is_true(#highlights > 0)
      
      -- Check for some expected content
      local has_header = false
      local has_test1 = false
      local has_test2 = false
      local has_summary = false
      
      for _, line in ipairs(lines) do
        if line == "Test Results" then has_header = true end
        if line:match("Test1") then has_test1 = true end
        if line:match("Test2") then has_test2 = true end
        if line:match("Total: %d+ passed, %d+ failed") then has_summary = true end
      end
      
      assert.is_true(has_header)
      assert.is_true(has_test1)
      assert.is_true(has_test2)
      assert.is_true(has_summary)
    end)
  end)

  describe("display_results", function()
    it("should use snacks.nvim when available", function()
      -- Mock parse_report and format_results
      report.parse_report = function() 
        return {
          TestSuite1 = {
            name = "TestSuite1",
            tests = { { name = "Test1", status = "PASSED", time = 0.1 } }
          }
        }
      end
      
      report.format_results = function() 
        return { "Test Results", "Line 2" }, { { line = 0, col_start = 0, col_end = -1, hl_group = "GdUnit4Header" } }
      end
      
      -- Mock Snacks.win to check if it's called
      local snacks_called = false
      local mock_win = { buf = 1001, win = 2001 }
      _G.Snacks.win = function(opts)
        snacks_called = true
        assert.equals("GdUnit4 Test Results", opts.title)
        assert.equals("bottom_right", opts.position)
        return mock_win
      end
      
      local result = report.display_results("/project", "reports", "bottom_right")
      
      assert.is_true(snacks_called)
      assert.equals(result, mock_win)
    end)
    
    it("should fall back to native window when snacks is not available", function()
      -- Disable snacks
      report.setup({ use_snacks = false })
      
      -- Mock parse_report and format_results
      report.parse_report = function() 
        return {
          TestSuite1 = {
            name = "TestSuite1",
            tests = { { name = "Test1", status = "PASSED", time = 0.1 } }
          }
        }
      end
      
      report.format_results = function() 
        return { "Test Results", "Line 2" }, { { line = 0, col_start = 0, col_end = -1, hl_group = "GdUnit4Header" } }
      end
      
      -- Mock buffer and window creation
      local buf_created = false
      local win_created = false
      vim.api.nvim_create_buf = function()
        buf_created = true
        return 1001
      end
      
      vim.api.nvim_open_win = function()
        win_created = true
        return 2001
      end
      
      local result = report.display_results("/project", "reports", "bottom_right")
      
      assert.is_true(buf_created)
      assert.is_true(win_created)
      assert.equals(2001, result)
    end)
  end)
end)
