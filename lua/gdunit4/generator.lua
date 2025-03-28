-- generator.lua - Simplified test generator for GdUnit4
-- Handles generating test files from C# classes

local M = {}

-- Helper functions for parameter handling
local function parse_parameters(params_text)
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

-- Extract type and name from a parameter string
local function extract_type_and_name(param_text)
  return param_text:match '([%w_<>%.]+)%s+([%w_]+)'
end

-- Generate default values for parameters based on type
local function generate_parameter_values(params_text)
  local params = parse_parameters(params_text)
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

-- Generate a test method for a given method info
function M.generate_test_method(method_info)
  -- Create test method name
  local test_name = 'Test_' .. method_info.name

  -- Generate method call with parameters
  local method_call = string.format('_sut.%s(%s)', method_info.name, generate_parameter_values(method_info.parameters))

  -- Add result capture for non-void methods
  if method_info.return_type and method_info.return_type ~= 'void' then
    method_call = string.format('var result = %s', method_call)
  end

  -- Create complete test method
  return string.format(
    [[
    [TestCase]
    public void %s()
    {
        // Arrange
        AssertThat(_sut).IsNotNull();

        // Act
        %s;

        // Assert
        // TODO: Add assertions for %s
    }]],
    test_name,
    method_call,
    method_info.name
  )
end

-- Generate constructor setup code
function M.generate_constructor_setup(file_data)
  if not file_data.constructor_params or file_data.constructor_params == '' then
    return '', '', '' -- No constructor parameters
  end

  local field_declarations = {}
  local initializations = {}
  local constructor_args = {}

  -- Process constructor parameters
  local params = parse_parameters(file_data.constructor_params)
  for _, param in ipairs(params) do
    local param_type, param_name = extract_type_and_name(param)
    if param_type and param_name then
      -- Add field declaration
      table.insert(field_declarations, string.format('    private %s _%s;', param_type, param_name))

      -- Generate initialization based on type
      local init_value = ({
        string = '        _%s = "test";',
        int = '        _%s = 1;',
        float = '        _%s = 1.0f;',
        double = '        _%s = 1.0;',
        bool = '        _%s = false;',
      })[param_type:lower()] or '        _%s = new %s();'

      table.insert(initializations, string.format(init_value, param_name, param_type))

      -- Add to constructor arguments
      table.insert(constructor_args, '_' .. param_name)
    end
  end

  return table.concat(field_declarations, '\n'), table.concat(initializations, '\n'), table.concat(constructor_args, ', ')
end

-- Generate complete test class
function M.generate_test_class(file_data)
  -- Generate constructor related code
  local field_declarations, initializations, constructor_args = M.generate_constructor_setup(file_data)

  -- Generate test methods for all public methods
  local test_methods = {}
  for _, method_info in ipairs(file_data.methods) do
    table.insert(test_methods, M.generate_test_method(method_info))
  end

  -- Default test method if no methods were found
  if #test_methods == 0 then
    table.insert(
      test_methods,
      [[
    [TestCase]
    public void Test_DefaultBehavior()
    {
        // Arrange
        AssertThat(_sut).IsNotNull();

        // Act & Assert
        // TODO: Add meaningful tests
    }]]
    )
  end

  -- Generate complete test class
  return string.format(
    [[
namespace %s;

using GdUnit4;
using static GdUnit4.Assertions;

[TestSuite]
public class %sTest
{
    private %s? _sut;
%s

    [Before]
    public void Setup()
    {
%s
        _sut = AutoFree(new %s(%s));
        AssertThat(_sut).IsNotNull();
    }

    [After]
    public void TearDown()
    {
        // Clean up resources if needed
    }

%s
}]],
    file_data.namespace or 'DefaultNamespace',
    file_data.class_name,
    file_data.class_name,
    field_declarations,
    initializations,
    file_data.class_name,
    constructor_args,
    table.concat(test_methods, '\n\n')
  )
end

return M
