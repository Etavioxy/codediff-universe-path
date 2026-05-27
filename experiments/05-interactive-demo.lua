-- Experiment 05: Universe-Path 命名 x codediff 侧栏（explorer）展示验证
-- 策略: 用 universe-path 名作为假 git status 条目
--   → explorer 侧栏直接显示 /pattern/ 等命名（%: 是输入语法，不显示）
--   → monkey-patch explorer.on_file_select 拦截文件加载
--   → 将 scheme 内容填充到 diff buffer
-- 使用: :source experiments/05-interactive-demo.lua → :lua _G.exp05.next()

local cwd = vim.fn.getcwd()
vim.opt.rtp:prepend(cwd)
vim.cmd('runtime! plugin/*.lua plugin/*.vim')
vim.cmd("filetype plugin on")
vim.cmd("syntax enable")

_G.exp05 = {}
_G.exp05.current = 1

-- 临时 git repo
local function setup_temp_repo()
  local tmpdir = vim.fn.tempname() .. "_codediff_exp05"
  vim.fn.mkdir(tmpdir, "p")
  vim.fn.system({ "git", "-C", tmpdir, "init" })
  vim.fn.system({ "git", "-C", tmpdir, "config", "user.email", "test@test" })
  vim.fn.system({ "git", "-C", tmpdir, "config", "user.name", "Test" })
  local sample_path = tmpdir .. "/sample.lua"
  local f = io.open(sample_path, "w")
  f:write("local M = {}\n\nfunction M.hello(name)\n  return \"Hello \" .. name\nend\n\nreturn M\n")
  f:close()
  vim.fn.system({ "git", "-C", tmpdir, "add", "sample.lua" })
  vim.fn.system({ "git", "-C", tmpdir, "commit", "-m", "init" })
  f = io.open(sample_path, "w")
  f:write("local M = {}\n\nfunction M.hello(name, greeting)\n  return greeting .. \" \" .. name\nend\n\nreturn M\n")
  f:close()
  _G.exp05.tmpdir = tmpdir
  return tmpdir
end

-- 5 种 universe-path 命名方案
-- display = 显示在侧栏/winbar/buffer 名中的路径（不含 %: 输入前缀）
-- input   = 通过 :edit %:/pattern/ 打开的命令（% 是 Vim 输入快捷方式）
_G.exp05.schemes = {
  {
    name = "pattern locator",
    original = "/function M.hello|end/",
    modified = "/function M.hello|end/-modified",
    input = "%:/function M.hello|end/",
    ft = "lua",
    orig_lines = { "function M.hello(name)", "  return \"Hello \" .. name", "end" },
    mod_lines =  { "function M.hello(name, greeting)", "  return greeting .. \" \" .. name  -- fixed", "end" },
  },
  {
    name = "range locator",
    original = "/1-3",
    modified = "/1-3/-modified",
    input = "%:1-3",
    ft = "lua",
    orig_lines = { "local M = {}", "", "return M" },
    mod_lines =  { "local M = {}", "M.version = '1.0'", "return M" },
  },
  {
    name = "pattern + modifier",
    original = "/def greet|return/",
    modified = "/def greet|return/-staged",
    input = "%:/def greet|return/",
    ft = "python",
    orig_lines = { "def greet(name):", "    return f'Hello {name}'" },
    mod_lines =  { "def greet(name):", "    return f'Hi {name}!'" },
  },
  {
    name = "nested path + range",
    original = "/src/utils.lua:1-3",
    modified = "/src/utils.lua:1-3/-modified",
    input = "%:/src/utils.lua:1-3",
    ft = "lua",
    orig_lines = { "local M = {}", "", "return M" },
    mod_lines =  { "local M = {}", "M.version = '1.0'", "return M" },
  },
  {
    name = "no-extension pattern",
    original = "/block/",
    modified = "/block/-modified",
    input = "%:/block/",
    ft = "lua",
    orig_lines = { "{", "  key = 'val'", "}" },
    mod_lines =  { "{", "  key = 42", "}" },
  },
}

function _G.exp05.find_scheme(path)
  for _, s in ipairs(_G.exp05.schemes) do
    if s.original == path or s.modified == path then
      return s
    end
  end
  return nil
end

function _G.exp05.show(scheme_index)
  _G.exp05.current = scheme_index or 1
  local s = _G.exp05.schemes[_G.exp05.current]
  if not s then return end

  if _G.exp05.tab and pcall(vim.api.nvim_win_is_valid, _G.exp05.tab) then
    pcall(vim.api.nvim_set_current_tabpage, _G.exp05.tab)
    pcall(vim.cmd, "tabclose!")
  end

  -- Hidden buffers for :buffers verification
  local h_orig = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(h_orig, 0, -1, false, s.orig_lines)
  vim.bo[h_orig].filetype = s.ft
  vim.api.nvim_buf_set_name(h_orig, s.original)
  vim.bo[h_orig].bufhidden = "hide"
  vim.bo[h_orig].buflisted = true

  local h_mod = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(h_mod, 0, -1, false, s.mod_lines)
  vim.bo[h_mod].filetype = s.ft
  vim.api.nvim_buf_set_name(h_mod, s.modified)
  vim.bo[h_mod].bufhidden = "hide"
  vim.bo[h_mod].buflisted = true

  -- 用 universe-path 显示名作为假 git status 条目
  local view = require("codediff.ui.view")
  local display_path = s.original  -- e.g. "/function M.hello|end/"
  local result = view.create({
    mode = "explorer",
    git_root = _G.exp05.tmpdir,
    original_path = nil,
    modified_path = nil,
    explorer_data = {
      status_result = {
        unstaged = { { path = display_path, status = "M" } },
        staged = {},
        conflicts = {},
      },
    },
  }, s.ft)

  local tabpage = vim.api.nvim_win_get_tabpage(result.original_win)
  local lifecycle = require("codediff.ui.lifecycle")
  local explorer = lifecycle.get_explorer(tabpage)

  -- 阻止 auto-refresh 用真实 git status 覆盖假数据
  if explorer then
    local refresh_mod = require("codediff.ui.explorer.refresh")
    local orig_refresh = refresh_mod.refresh
    refresh_mod.refresh = function(exp)
      local exp_tab = exp.winid and vim.api.nvim_win_is_valid(exp.winid)
        and vim.api.nvim_win_get_tabpage(exp.winid)
      if exp_tab == tabpage then
        return
      end
      return orig_refresh(exp)
    end
  end

  if explorer then
    local orig_on_file_select = explorer.on_file_select
    explorer.on_file_select = function(file_data, opts)
      local scheme = _G.exp05.find_scheme(file_data.path)
      if scheme then
        explorer.current_file_path = file_data.path
        explorer.current_file_group = file_data.group
        explorer.current_selection = vim.deepcopy(file_data)
        explorer.tree:render()

        local ob, mb = lifecycle.get_buffers(tabpage)
        if ob and vim.api.nvim_buf_is_valid(ob) then
          vim.api.nvim_buf_set_lines(ob, 0, -1, false, scheme.orig_lines)
          vim.bo[ob].filetype = scheme.ft
          pcall(vim.api.nvim_buf_set_name, ob, scheme.original .. " [diff]")
        end
        if mb and vim.api.nvim_buf_is_valid(mb) then
          vim.api.nvim_buf_set_lines(mb, 0, -1, false, scheme.mod_lines)
          vim.bo[mb].filetype = scheme.ft
          pcall(vim.api.nvim_buf_set_name, mb, scheme.modified .. " [diff]")
        end

        vim.cmd("redraw!")

        if result.original_win and vim.api.nvim_win_is_valid(result.original_win) then
          vim.wo[result.original_win].winbar = "%#Keyword#" .. scheme.original
        end
        if result.modified_win and vim.api.nvim_win_is_valid(result.modified_win) then
          vim.wo[result.modified_win].winbar = "%#String#" .. scheme.modified
        end
      else
        orig_on_file_select(file_data, opts)
      end
    end
  end

  _G.exp05.tab = tabpage
  _G.exp05.result = result
  _G.exp05.scheme = s
  _G.exp05.hidden_bufs = { orig = h_orig, mod = h_mod }

  vim.cmd("messages clear")
  vim.cmd("redraw!")
  print(string.format("[%d/%d] %s | :e %s",
    _G.exp05.current, #_G.exp05.schemes, s.name, s.input))
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

require("codediff").setup()
local tmpdir = setup_temp_repo()
print("=== Exp05: Universe-Path x Explorer Sidebar ===")
print("  " .. #_G.exp05.schemes .. " schemes. :lua _G.exp05.next() to cycle")
_G.exp05.show(1)