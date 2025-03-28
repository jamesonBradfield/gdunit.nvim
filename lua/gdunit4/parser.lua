-- parser.lua - Simplified C# parser for GdUnit4
-- Handles parsing C# files to extract class structure for test generation

local M = {}

-- Query for extracting class information from C# files
local CS_QUERY = [[
    ; Get the namespace definition
    (namespace_declaration
        name: (identifier) @file.namespace
    )

    ; Get the class name and constructor
    (class_declaration
        name: (identifier) @file.class_name
        (constructor_declaration
            parameters: (parameter_list) @constructor.params
        )?
    )

    ; Get all method declarations and their components
    (method_declaration
        (modifier)* @method.modifier
        returns: [
            (predefined_type) @method.return_type
            (identifier) @method.return_type
            (type_argument_list) @method.return_type
            (generic_name) @method.return_type
        ]
        name: (identifier) @method.name
        parameters: (parameter_list) @method.params
    ) @method.declaration
]]

-- Helper function to get node text
local function get_node_text(node, content)
  return node and vim.treesitter.get_node_text(node, content)
end

-- Parse a C# file and extract class structure
function M.parse_file(file_path)
  -- Check if file exists
  if vim.fn.filereadable(file_path) ~= 1 then
    vim.notify('File does not exist: ' .. file_path, vim.log.levels.ERROR)
    return nil
  end

  -- Check if file is a C# file
  if not file_path:match '%.cs$' then
    vim.notify('Not a C# file: ' .. file_path, vim.log.levels.ERROR)
    return nil
  end

  -- Read file content
  local content = table.concat(vim.fn.readfile(file_path), '\n')

  -- Check if TreeSitter is available
  if not vim.treesitter then
    vim.notify('TreeSitter not available, parser cannot run', vim.log.levels.ERROR)
    return nil
  end

  -- Check if C# parser is available
  if not pcall(function()
    vim.treesitter.language.require_language('c_sharp', nil, true)
  end) then
    vim.notify('C# TreeSitter parser not available', vim.log.levels.ERROR)
    return nil
  end

  -- Initialize TreeSitter parser
  local parser = vim.treesitter.get_string_parser(content, 'c_sharp')

  -- Parse content
  local tree = parser:parse()[1]
  local root = tree:root()

  -- Create query
  local query = vim.treesitter.query.parse('c_sharp', CS_QUERY)

  -- Initialize data structure
  local file_data = {
    namespace = nil,
    class_name = nil,
    constructor_params = nil,
    methods = {},
  }

  -- Current method being processed
  local current_method = nil
  local method_modifiers = {}

  -- Process query matches
  for id, node in query:iter_captures(root, content, 0, -1) do
    local capture_name = query.captures[id]

    if capture_name == 'file.namespace' then
      file_data.namespace = get_node_text(node, content)
    elseif capture_name == 'file.class_name' then
      file_data.class_name = get_node_text(node, content)
    elseif capture_name == 'constructor.params' then
      file_data.constructor_params = get_node_text(node, content)
    elseif capture_name == 'method.declaration' then
      current_method = {}
      method_modifiers = {}
    elseif capture_name == 'method.modifier' then
      table.insert(method_modifiers, get_node_text(node, content))
    elseif capture_name == 'method.name' and current_method then
      current_method.name = get_node_text(node, content)
    elseif capture_name == 'method.return_type' and current_method then
      current_method.return_type = get_node_text(node, content)
    elseif capture_name == 'method.params' and current_method then
      current_method.parameters = get_node_text(node, content)

      -- Add method if it's public and not a property accessor
      if vim.tbl_contains(method_modifiers, 'public') and current_method.name and not current_method.name:match '^[gs]et_' then
        table.insert(file_data.methods, current_method)
      end

      -- Reset current method
      current_method = nil
      method_modifiers = {}
    end
  end

  -- Validate that we found necessary info
  if not file_data.class_name then
    vim.notify('No class found in file', vim.log.levels.ERROR)
    return nil
  end

  -- If no namespace found, use default
  if not file_data.namespace then
    file_data.namespace = 'GodotGame'
    vim.notify('No namespace found, using default: GodotGame', vim.log.levels.WARN)
  end

  return file_data
end

-- Parse parameters from parameter list text
function M.parse_parameters(params_text)
  if not params_text or params_text == '' then
    return {}
  end

  -- Remove parentheses
  params_text = params_text:gsub('^%(', ''):gsub('%)$', '')

  local params = {}
  for param in params_text:gmatch '[^,]+' do
    param = param:match '^%s*(.-)%s*$' -- Trim whitespace
    if param ~= '' then
      table.insert(params, param)
    end
  end

  return params
end

-- Generate default values for parameters based on type
function M.generate_parameter_values(params_text)
  local params = M.parse_parameters(params_text)
  local values = {}

  for _, param in ipairs(params) do
    local param_type = param:match '([%w_<>]+)%s+[%w_]+'
    if param_type then
      -- Default values by type
      local default_value = ({
        string = '""',
        int = '0',
        float = '0.0f',
        double = '0.0',
        bool = 'false',
      })[param_type:lower()] or 'null'

      table.insert(values, default_value)
    end
  end

  return table.concat(values, ', ')
end

-- Extract type and name from a parameter string
function M.extract_type_and_name(param_text)
  return param_text:match '([%w_<>%.]+)%s+([%w_]+)'
end

return M
