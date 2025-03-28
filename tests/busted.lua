#!/usr/bin/env -S nvim -l

-- Set up isolated test environment
vim.env.LAZY_STDPATH = ".tests"
load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"))()

-- Debug output
print("Setting up test environment...")
print("Current directory: " .. vim.fn.getcwd())

-- Use lazy.minit.busted to properly set up the Busted testing environment
-- This will automatically add the lunarmodules/busted package
-- and set up the necessary environment for testing
require("lazy.minit").busted({
  -- Add your plugin dependencies here
  spec = {
    "nvim-lua/plenary.nvim",  -- Common utility functions
    "nvim-treesitter/nvim-treesitter", -- For XML parsing
  }
})

-- Add the plugin code path to runtime path
local plugin_path = vim.fn.getcwd()
vim.opt.runtimepath:prepend(plugin_path)

-- Stub the global Snacks for testing
_G.Snacks = {
  win = function(opts)
    -- Return a mock window object for testing
    return {
      buf = 1001, -- Mock buffer ID
      win = 2001, -- Mock window ID
      title = opts.title,
      position = opts.position,
      opts = opts,
      close = function() end
    }
  end
}

-- At this point, the busted functions (describe, it, etc.) should be available
-- and tests will run automatically

print("Test environment setup complete!")
