-- awiwi ftdetect (ports ftdetect/awiwi.vim). Assigns the `awiwi` filetype
-- family to markdown files under g:awiwi_home, and binds the aP/iP code-block
-- text objects to every markdown buffer. See handovers/lua-port/init.md §80-83.

local home = vim.g.awiwi_home
if not home or home == "" then
  return
end

--- Only override an empty or exactly-`markdown` filetype (user's own ftdetect
--- wins otherwise) — the vimscript `s:add_awiwi_filetype` guard.
local function set_ft(type_)
  local ft = vim.bo.filetype
  if ft == "" or ft == "markdown" then
    vim.bo.filetype = type_
  end
end

local function add_code_block_textobjects()
  local opts = { buffer = true, silent = true }
  vim.keymap.set("x", "aP", ':<C-u>lua require("awiwi.util").select_code_block(true)<CR>', opts)
  vim.keymap.set("x", "iP", ':<C-u>lua require("awiwi.util").select_code_block(false)<CR>', opts)
  vim.keymap.set("o", "aP", 'V:<C-u>lua require("awiwi.util").select_code_block(true)<CR>', opts)
  vim.keymap.set("o", "iP", 'V:<C-u>lua require("awiwi.util").select_code_block(false)<CR>', opts)
end

local group = vim.api.nvim_create_augroup("awiwiFtDetect", { clear = true })

-- Every markdown buffer (not just awiwi ones) gets the code-block text objects.
vim.api.nvim_create_autocmd("BufRead", {
  group = group,
  pattern = "*.md",
  callback = add_code_block_textobjects,
})

local rules = {
  { home .. "/journal/**/*.md", "awiwi" },
  { home .. "/assets/**/*", "awiwi.asset" },
  { home .. "/recipes/*", "awiwi.recipe" },
  { home .. "/recipes/**/*", "awiwi.recipe" },
  { home .. "/todos/*.md", "awiwi.todo" },
}
for _, dir in pairs(vim.g.awiwi_external_dirs or {}) do
  rules[#rules + 1] = { vim.fn.expand(dir) .. "/*.md", "awiwi" }
end

for _, rule in ipairs(rules) do
  vim.api.nvim_create_autocmd({ "BufNewFile", "BufReadPost", "BufWinEnter" }, {
    group = group,
    pattern = rule[1],
    callback = function()
      set_ft(rule[2])
    end,
  })
end
