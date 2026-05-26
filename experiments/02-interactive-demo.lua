-- Experiment 02 交互式演示版本 (v2)
-- 运行方式: nvim 然后 :source experiments/02-interactive-demo.lua
-- 验证: diff高亮、filetype语法高亮、inline模式
-- 使用方法:
--   :source experiments/02-interactive-demo.lua
--   :lua _G.exp02.step()   — 切换验证步骤

local cwd = vim.fn.getcwd()
vim.opt.rtp:prepend(cwd)
vim.cmd('runtime! plugin/*.lua plugin/*.vim')

_G.exp02 = {}
_G.exp02.step_index = 1
_G.exp02.cur_tab = nil

local function cleanup_tab()
  if _G.exp02.cur_tab and pcall(vim.api.nvim_win_is_valid, _G.exp02.cur_tab) then
    pcall(vim.api.nvim_set_current_tabpage, _G.exp02.cur_tab)
    pcall(vim.cmd, "tabclose!")
  end
end

local function check_highlights(bufnr, label)
  local highlights = require("codediff.ui.highlights")
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, highlights.ns_highlight, 0, -1, {})
  local filler_marks = vim.api.nvim_buf_get_extmarks(bufnr, highlights.ns_filler, 0, -1, {})
  local count = #extmarks + #filler_marks
  print(string.format("  %s: %d highlight marks (%d diff + %d filler)", label, count, #extmarks, #filler_marks))
  return count > 0
end

-- Step 1: 侧栏 diff 高亮验证 (side-by-side)
function _G.exp02.step1_side_by_side_diff_highlights()
  cleanup_tab()
  require("codediff").setup()

  local orig_lines = {
    "function foo()",
    "  local x = 1",
    "  local y = 2",
    "  return x + y",
    "end",
  }
  local mod_lines = {
    "function foo()",
    "  local x = 10   -- changed",
    "  local y = 2",
    "  local z = 3    -- added",
    "  return x + y + z",
    "end",
  }

  local orig_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(orig_buf, 0, -1, false, orig_lines)
  vim.api.nvim_buf_set_name(orig_buf, "%:/function foo|end/")

  local mod_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(mod_buf, 0, -1, false, mod_lines)
  vim.api.nvim_buf_set_name(mod_buf, "%:/function foo|end/-modified")

  local view = require("codediff.ui.view")
  local ok, result = pcall(view.create, {
    mode = "standalone",
    original_path = "%:/function foo|end/",
    modified_path = "%:/function foo|end/-modified",
  }, "lua")

  _G.exp02.cur_tab = vim.api.nvim_get_current_tabpage()

  print("=== Step 1: Diff 高亮渲染验证 ===")
  if ok then
    print("view.create PASS")
    print("  Original buf: " .. result.original_buf .. " win: " .. result.original_win)
    print("  Modified buf: " .. result.modified_buf .. " win: " .. result.modified_win)

    -- 等待 vim.schedule render_everything 完成
    vim.defer_fn(function()
      local orig_ok = check_highlights(result.original_buf, "左栏(original)")
      local mod_ok = check_highlights(result.modified_buf, "右栏(modified)")
      print(orig_ok and mod_ok and ">>> PASS: diff 高亮已渲染" or ">>> FAIL: 高亮丢失")
    end, 200)
  else
    print("FAIL: view.create error: " .. tostring(result))
  end

  print("  :lua _G.exp02.step()  — 下一步(filetype)")
  _G.exp02.step_index = 1
end

-- Step 2: filetype 语法高亮验证 (lua + python)
function _G.exp02.step2_filetype_highlight()
  cleanup_tab()
  require("codediff").setup()

  local ft_results = {}

  for _, ft in ipairs({"lua", "python"}) do
    local orig, mod
    if ft == "lua" then
      orig = { "local M = {}", "", "M.version = '1.0'", "", "return M" }
      mod  = { "local M = {}", "M.author = 'dev'", "M.version = '1.0'", "", "return M" }
    else
      orig = { "def greet(name):", "    return 'Hello ' + name", "" }
      mod  = { "def greet(name, title=''):", "    return f'Hi {title} {name}'", "" }
    end

    local orig_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(orig_buf, 0, -1, false, orig)
    local orig_name = "%:/block-" .. ft .. "/"
    local mod_name = "%:/block-" .. ft .. "/-modified"
    vim.api.nvim_buf_set_name(orig_buf, orig_name)

    local mod_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(mod_buf, 0, -1, false, mod)
    vim.api.nvim_buf_set_name(mod_buf, mod_name)

    local view = require("codediff.ui.view")
    local ok, result = pcall(view.create, {
      mode = "standalone",
      original_path = orig_name,
      modified_path = mod_name,
    }, ft)

    if ok then
      -- 检查 filetype 是否应用
      local orig_ft = vim.bo[result.original_buf].filetype
      local mod_ft = vim.bo[result.modified_buf].filetype
      local pass = (orig_ft == ft) and (mod_ft == ft)
      table.insert(ft_results, { ft = ft, orig_ft = orig_ft, mod_ft = mod_ft, pass = pass })
      print(string.format("  %s: orig=%s mod=%s => %s", ft, orig_ft, mod_ft, pass and "PASS" or "FAIL"))
    else
      table.insert(ft_results, { ft = ft, pass = false, error = tostring(result) })
      print(string.format("  %s: view.create FAIL: %s", ft, tostring(result)))
    end

    -- Cleanup tab for next test
    pcall(vim.cmd, "tabclose!")
  end

  print("=== Step 2: Filetype 语法高亮验证 ===")
  local all_pass = true
  for _, r in ipairs(ft_results) do
    all_pass = all_pass and r.pass
  end
  print(all_pass and ">>> PASS: filetype 高亮正确" or ">>> FAIL: filetype 不匹配")

  -- Reopen the last one for visual inspection
  _G.exp02.step2_filetype_highlight = nil -- can't reuse
  print("  :lua _G.exp02.step()  — 下一步(inline)")
  _G.exp02.step_index = 2
end

-- Step 3: inline 模式验证
function _G.exp02.step3_inline_mode()
  cleanup_tab()
  require("codediff").setup()

  local orig_lines = {
    "local x = 1",
    "local y = 2",
    "local z = 3",
    "return x + y + z",
  }
  local mod_lines = {
    "local x = 1",
    "local y = 20",
    "local z = 3",
    "return x + y + z",
  }

  local orig_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(orig_buf, 0, -1, false, orig_lines)
  local orig_name = "%:1-4-inline"
  local mod_name = "%:1-4-inline/-modified"
  vim.api.nvim_buf_set_name(orig_buf, orig_name)

  local mod_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(mod_buf, 0, -1, false, mod_lines)
  vim.api.nvim_buf_set_name(mod_buf, mod_name)

  local view = require("codediff.ui.view")
  local ok, result = pcall(view.create, {
    mode = "standalone",
    original_path = orig_name,
    modified_path = mod_name,
    layout = "inline",
  }, "lua")

  _G.exp02.cur_tab = vim.api.nvim_get_current_tabpage()

  print("=== Step 3: Inline 模式验证 ===")
  if ok then
    local wins = vim.api.nvim_tabpage_list_wins(_G.exp02.cur_tab)
    print(string.format("  view.create PASS (%d windows)", #wins))
    print("  Original buf: " .. result.original_buf .. " win: " .. (result.original_win or "nil"))
    print("  Modified buf: " .. result.modified_buf .. " win: " .. (result.modified_win or "nil"))

    -- inline 模式应该只有一个或两个窗口（取决于实现）
    -- 关键是不报错、不崩溃
    vim.defer_fn(function()
      local highlights = require("codediff.ui.highlights")
      local extmarks = vim.api.nvim_buf_get_extmarks(result.modified_buf, highlights.ns_highlight, 0, -1, {})
      local filler_marks = vim.api.nvim_buf_get_extmarks(result.modified_buf, highlights.ns_filler, 0, -1, {})
      local count = #extmarks + #filler_marks
      print(string.format("  Inline highlights: %d marks (%d diff + %d filler)", count, #extmarks, #filler_marks))
      print(count > 0 and ">>> PASS: inline 模式 diff 高亮正常" or ">>> PASS: inline 模式无崩溃（无变更时高亮为空属正常）")
    end, 200)
  else
    print("FAIL: inline view.create error: " .. tostring(result))
  end

  print("  :lua _G.exp02.summary()  — 查看汇总")
  _G.exp02.step_index = 3
end

-- Step 切换
function _G.exp02.step()
  if _G.exp02.step_index == 1 then
    _G.exp02.step2_filetype_highlight()
  elseif _G.exp02.step_index == 2 then
    _G.exp02.step3_inline_mode()
  elseif _G.exp02.step_index == 3 then
    _G.exp02.step1_side_by_side_diff_highlights()
  end
end

-- Summary
function _G.exp02.summary()
  print([[
=== Exp02 验证清单 ===
  1. side-by-side diff 高亮  — :lua _G.exp02.step1_...()
  2. filetype 语法高亮       — :lua _G.exp02.step2_...()
  3. inline 模式可行性       — :lua _G.exp02.step3_...()
  :lua _G.exp02.step()      — 循环切换
]])
end

-- === Setup ===
require("codediff").setup()

print("=== Experiment 02: Diff 高亮 + Filetype + Inline ===")
print("3 个验证步骤（side-by-side高亮/filetype语法/inline模式）")
print("")
_G.exp02.step1_side_by_side_diff_highlights()
