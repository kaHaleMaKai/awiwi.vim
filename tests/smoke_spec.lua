describe("runner", function()
  it("eq works", function() eq({1, "a"}, {1, "a"}) end)
  it("nvim api available", function() ok(vim.api.nvim_create_buf(false, true) > 0) end)
end)
