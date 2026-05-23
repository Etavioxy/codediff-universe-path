-- Experiment 05: Universe-Path 命名在 codediff 侧栏中的展示验证
-- 运行: nvim 然后 :source experiments/05-interactive-demo.lua
-- 验证: universe-path 命名在 codediff side-by-side 视图中正确显示
--       侧栏 buffer 名称完整保留 %:/pattern/ 等特殊字符
-- 使用方法:
--   :source experiments/05-interactive-demo.lua  — 直接打开 diff 视图
--   :lua _G.exp05.next()                        — 切换下一个命名方案
--   :lua _G.exp05.list()                        — 显示 :buffers 列表

_G.exp05 = {}
_G.exp05.current = 1

-- === 命名方案 ===
_G.exp05.schemes = {
  {
    name = "pattern locator",
    original = "%:/function foo|end/",
    modified = "%:/function foo|end/-modified",
    ft = "lua",
    orig_lines = { "function foo()", "  local x = 1", "  return x", "end" },
    mod_lines =  { "function foo()", "  local x = 10   -- changed", "  return x", "end" },
  },
  {
    name = "range locator",
    original = "%:1-4",
    modified = "%:1-4/-modified",
    ft = "lua",
    orig_lines = { "function bar()", "  local y = 2", "  return y", "end" },
    mod_lines =  { "function bar()", "  local y = 20", "  return y * 2", "end" },
  },
  {
    name = "pattern + modifier",
    original = "%:/def greet|return/",
    modified = "%:/def greet|return/-staged",
    ft = "python",
    orig_lines = { "def greet(name):", "    return f'Hello {name}'" },
    mod_lines =  { "def greet(name):", "    return f'Hi {name}!'" },
  },
  {
    name = "nested path + range",
    original = "%:/src/utils.lua:1-3",
    modified = "%:/src/utils.lua:1-3/-modified",
    ft = "lua",
    orig_lines = { "local M = {}", "", "return M" },
    mod_lines =  { "local M = {}", "M.version = '1.0'", "return M" },
  },
  {
    name = "no-extension pattern",
    original = "%:/block/",
    modified = "%:/block/-modified",
    ft = "lua",
    orig_lines = { "{", "  key = 'val'", "}" },
    mod_lines =  { "{", "  key = 42", "}" },
  },
}

-- === 在 diff 视图中设置 winbar 显示 universe-path 名称 ===
function _G.exp05.show(scheme_index)
  _G.exp05.current = scheme_index or 1
  local s = _G.exp05.schemes[_G.exp05.current]
  if not s then
    print("Invalid scheme index")
    return
  end

  -- 创建 buffer
  local orig_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(orig_buf, 0, -1, false, s.orig_lines)
  vim.api.nvim_buf_set_name(orig_buf, s.original)

  local mod_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(mod_buf, 0, -1, false, s.mod_lines)
  vim.api.nvim_buf_set_name(mod_buf, s.modified)

  -- 关闭所有旧窗口，准备新 diff
  vim.cmd("tabnew")
  local tab = vim.api.nvim_get_current_tabpage()

  local view = require("codediff.ui.view")
  local result = view.create({
    mode = "standalone",
    original_path = s.original,
    modified_path = s.modified,
  }, s.ft)

  -- 设置 winbar 显示 universe-path 名称
  vim.wo[result.original_win].winbar = "%#Keyword#" .. s.original
  vim.wo[result.modified_win].winbar = "%#String#" .. s.modified

  _G.exp05.tab = tab
  _G.exp05.result = result
  _G.exp05.scheme = s

  print(string.format("=== 方案 %d/%d: %s ===", _G.exp05.current, #_G.exp05.schemes, s.name))
  print(string.format("  左栏: %s (%s)", s.original, s.ft))
  print(string.format("  右栏: %s (%s)", s.modified, s.ft))
  print("  >>> 观察左右侧栏的 winbar 标题是否完整显示 %:/... 命名")
  print("  :lua _G.exp05.next()    — 下一个方案")
  print("  :lua _G.exp05.list()   — :buffers 列表")
end

function _G.exp05.next()
  _G.exp05.current = _G.exp05.current + 1
  if _G.exp05.current > #_G.exp05.schemes then
    _G.exp05.current = 1
  end
  _G.exp05.show(_G.exp05.current)
end

function _G.exp05.list()
  vim.cmd("buffers")
end

-- === Setup ===
local cwd = vim.fn.getcwd()
vim.opt.rtp:prepend(cwd)
vim.cmd('runtime! plugin/*.lua plugin/*.vim')
require("codediff").setup()

print("=== Experiment 05: Universe-Path 命名 × codediff 侧栏展示 ===")
print(string.format("%d 种命名方案（pattern/range/modifier/nested/noext）", #_G.exp05.schemes))
print("")
_G.exp05.show(1)