describe("Simple test", function()
  it("should pass", function()
    assert(true, "This test should always pass")
  end)
  
  it("can access vim API", function()
    assert(vim ~= nil, "Vim API should be available")
    assert(vim.fn ~= nil, "Vim function interface should be available")
  end)
end)
