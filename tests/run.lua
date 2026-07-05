-- Zero-dependency spec runner for the Lua port.
-- Usage: nvim --clean --headless -l tests/run.lua [tests/<mod>_spec.lua ...]
-- Globals for specs: describe(name, fn), it(name, fn), eq(expected, actual), ok(cond, msg)

local root = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(vim.fn.fnamemodify(arg[0] or "tests/run.lua", ":p"))))
vim.opt.runtimepath:prepend(root)

local failures, passed = {}, 0
local prefix = ""

function describe(name, fn)
  local outer = prefix
  prefix = prefix .. name .. " > "
  fn()
  prefix = outer
end

function it(name, fn)
  local ok_, err = xpcall(fn, debug.traceback)
  if ok_ then
    passed = passed + 1
  else
    failures[#failures + 1] = { name = prefix .. name, err = err }
  end
end

function eq(expected, actual)
  if not vim.deep_equal(expected, actual) then
    error(("expected %s, got %s"):format(vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

function ok(cond, msg)
  if not cond then error(msg or "assertion failed", 2) end
end

local files = {}
for i = 1, #arg do files[#files + 1] = arg[i] end
if #files == 0 then
  files = vim.fn.glob(root .. "/tests/*_spec.lua", false, true)
end
table.sort(files)

for _, f in ipairs(files) do
  dofile(f)
end

for _, f in ipairs(failures) do
  io.write(("FAIL %s\n%s\n\n"):format(f.name, f.err))
end
io.write(("%d passed, %d failed (%d files)\n"):format(passed, #failures, #files))
os.exit(#failures == 0 and 0 or 1)
