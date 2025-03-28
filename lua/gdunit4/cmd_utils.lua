-- cmd_utils.lua
-- Simplified command execution utilities for Godot plugins

local M = {}

-- Check if we have access to vim.notify_once (Neovim 0.8+)
local has_notify_once = vim.notify_once ~= nil

-- Default configuration
local config = {
	notify_commands = true, -- Show notifications for command execution
	notify_level = vim.log.levels.INFO,
	path_separator = vim.fn.has 'win32' == 1 and '\\' or '/',
	use_spinners = false, -- Simplified version doesn't use spinners
}

---Configure the command utilities
---@param opts table Configuration options
function M.setup(opts)
	if opts then
		for k, v in pairs(opts) do
			config[k] = v
		end
	end
	return M
end

---Simple logger function
---@param message string Message to log
---@param level number Vim log level (optional)
function M.log(message, level)
	if not message then
		return
	end

	level = level or config.notify_level

	-- Console notification
	if config.notify_commands then
		-- Use notify_once if available to avoid flooding
		if has_notify_once then
			vim.notify_once(message, level)
		else
			vim.notify(message, level)
		end
	end
end

---Escape spaces and special characters in path
---@param path string Path to escape
---@return string Escaped path
function M.escape_path(path)
	if vim.fn.has 'win32' == 1 then
		-- On Windows, wrap paths with spaces in quotes
		if path:match '%s' then
			return '"' .. path .. '"'
		end
		return path
	else
		-- On Unix, escape spaces with backslashes
		return path:gsub(' ', '\\ ')
	end
end

---Build a command from components
---@param base string Base command
---@param args table|nil Command arguments
---@return string Complete command string
function M.build_command(base, args)
	local cmd = base

	-- Add arguments
	if args then
		for _, arg in ipairs(args) do
			if arg:match '^%-' then
				-- Option flags (like -a or --debug)
				cmd = cmd .. ' ' .. arg
			else
				-- Paths or values that might need escaping
				cmd = cmd .. ' ' .. M.escape_path(arg)
			end
		end
	end

	return cmd
end

---Execute a command synchronously
---@param cmd string|table Command to execute
---@param opts table|nil Options for execution
---@return string Output of command
---@return number Exit code
function M.execute_sync(cmd, opts)
	opts = opts or {}

	-- Log the command
	if opts.notify ~= false and config.notify_commands then
		local cmd_str = type(cmd) == 'table' and table.concat(cmd, ' ') or cmd
		M.log('Executing: ' .. cmd_str)
	end

	-- Handle change of working directory
	local original_dir
	if opts.cwd then
		original_dir = vim.fn.getcwd()
		vim.fn.chdir(opts.cwd)
	end

	-- Execute the command
	local output = vim.fn.system(cmd)
	local exit_code = vim.v.shell_error
	if opts.callback ~= nil then
		opts.callback()
	end

	-- Restore original directory if changed
	if original_dir then
		vim.fn.chdir(original_dir)
	end
	-- Log result
	if opts.notify ~= false and config.notify_commands and exit_code ~= 0 then
		M.log('Command failed with exit code: ' .. exit_code, vim.log.levels.ERROR)
	end

	return output, exit_code
end

---Execute a command asynchronously
---@param cmd string|table Command to execute
---@param opts table|nil Options for execution
---@param callback function Callback function(output, success, error)
---@return table|nil Job handle if available
function M.execute_async(cmd, opts, callback)
	opts = opts or {}

	-- Create string representation for logging
	local cmd_str = type(cmd) == 'table' and table.concat(cmd, ' ') or cmd

	-- Log the command
	if opts.notify ~= false and config.notify_commands then
		M.log('Executing async: ' .. cmd_str)
	end

	-- Use vim.fn.jobstart for async execution
	if vim.fn.exists '*jobstart' == 1 then
		local output = {}
		local stderr = {}

		local job_opts = {
			on_stdout = function(_, data)
				if data and #data > 0 then
					vim.list_extend(output, data)
				end
			end,
			on_stderr = function(_, data)
				if data and #data > 0 then
					vim.list_extend(stderr, data)
				end
			end,
			on_exit = function(_, code)
				local success = code == 0
				local stdout = table.concat(output, '\n')
				local error_output = success and nil or table.concat(stderr, '\n')

				if callback then
					callback(stdout, success, error_output)
				end
			end,
			stdout_buffered = true,
			stderr_buffered = true,
			detach = opts.detach or false,
			cwd = opts.cwd,
		}

		local job_id = vim.fn.jobstart(cmd_str, job_opts)

		if job_id <= 0 then
			vim.schedule(function()
				local err_msg = 'Failed to start job (code: ' .. job_id .. ')'
				if callback then
					callback(nil, false, err_msg)
				end
			end)
			return nil
		end

		return {
			id = job_id,
			stop = function()
				vim.fn.jobstop(job_id)
			end,
		}
	else
		-- Fallback to synchronous execution if jobstart is not available
		vim.schedule(function()
			local output, exit_code = M.execute_sync(cmd, opts)
			if callback then
				callback(output, exit_code == 0, exit_code ~= 0 and output or nil)
			end
		end)

		-- Return a dummy handle
		return {
			stop = function() end,
		}
	end
end

---Kill processes by name or pattern
---@param process_name string Process name or pattern to kill
---@param callback function|nil Optional callback function(success)
function M.kill_process(process_name, callback)
	local kill_cmd
	if vim.fn.has 'win32' == 1 then
		kill_cmd = 'taskkill /F /IM ' .. process_name .. ' 2>nul'
	else
		kill_cmd = 'pkill -f "' .. process_name .. '" 2>/dev/null'
	end

	return M.execute_async(kill_cmd, { notify = false }, function(_, success)
		if callback then
			-- Wait a bit to ensure processes are killed before returning
			vim.defer_fn(function()
				callback(success)
			end, 300)
		end
	end)
end

---Check if a program is available in PATH
---@param program string Program name
---@return boolean True if available
function M.is_program_available(program)
	local cmd
	if vim.fn.has 'win32' == 1 then
		cmd = 'where ' .. program .. ' >nul 2>&1'
	else
		cmd = 'command -v ' .. program .. ' >/dev/null 2>&1'
	end

	local exit_code = os.execute(cmd)
	return exit_code == 0
end

return M
