-- Experiment 02 交互式演示版本 (v3)
-- 运行方式: nvim 然后 :source experiments/02-interactive-demo.lua
-- 验证: diff高亮 + filetype语法高亮 同时验证，inline模式
-- 使用方法:
--   :source experiments/02-interactive-demo.lua
--   :lua _G.exp02.step()   — 切换验证步骤

local cwd = vim.fn.getcwd()
vim.opt.rtp:prepend(cwd)
vim.cmd('runtime! plugin/*.lua plugin/*.vim')

-- Enable syntax highlighting (needed when running with -u NONE)
vim.cmd("filetype plugin on")
vim.cmd("syntax enable")
vim.cmd("colorscheme default")

_G.exp02 = {}
_G.exp02.step_index = 1
_G.exp02.cur_tab = nil

local function cleanup_tab()
  -- Delete named buffers to avoid E95 on re-creation
  for _, name in ipairs({ "%:/greet.lua", "%:/greet.lua/-modified", "%:/inline.lua", "%:/inline.lua/-modified" }) do
    local bufnr = vim.fn.bufnr(name)
    if bufnr ~= -1 then pcall(vim.api.nvim_buf_delete, bufnr, { force = true }) end
  end
  if _G.exp02.cur_tab and pcall(vim.api.nvim_tabpage_is_valid, _G.exp02.cur_tab) then
    pcall(vim.api.nvim_set_current_tabpage, _G.exp02.cur_tab)
    pcall(vim.cmd, "tabclose!")
  end
end

local function check_highlights(bufnr, label)
  local highlights = require("codediff.ui.highlights")
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, highlights.ns_highlight, 0, -1, {})
  local filler_marks = vim.api.nvim_buf_get_extmarks(bufnr, highlights.ns_filler, 0, -1, {})
  local count = #extmarks + #filler_marks
  local filetype = vim.bo[bufnr].filetype or "(none)"
  print(string.format("  %s: %d highlight marks (%d diff + %d filler), filetype=%s", label, count, #extmarks, #filler_marks, filetype))
  return count > 0, filetype
end

-- Step 1: side-by-side diff高亮 + filetype语法高亮 同时验证
function _G.exp02.step1_side_by_side()
  cleanup_tab()
  require("codediff").setup()

  local orig_lines = {
    "local M = {}",
    "",
    "function M.greet(name)",
    "  return 'Hello ' .. name",
    "end",
    "",
    "return M",
  }
  local mod_lines = {
    "local M = {}",
    "M.version = '1.0'",
    "",
    "function M.greet(name, title)",
    "  return string.format('Hi %s %s', title, name)",
    "end",
    "",
    "return M",
  }

  local orig_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(orig_buf, 0, -1, false, orig_lines)
  vim.api.nvim_buf_set_name(orig_buf, "%:/greet.lua")

  local mod_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(mod_buf, 0, -1, false, mod_lines)
  vim.api.nvim_buf_set_name(mod_buf, "%:/greet.lua/-modified")

  local view = require("codediff.ui.view")
  local ok, result = pcall(view.create, {
    mode = "standalone",
    original_path = "%:/greet.lua",
    modified_path = "%:/greet.lua/-modified",
  }, "lua")

  _G.exp02.cur_tab = vim.api.nvim_get_current_tabpage()

  print("=== Step 1: Diff高亮 + Filetype语法高亮 (同时验证) ===")
  if ok then
    print("view.create PASS")
    print("  Original buf: " .. result.original_buf .. " win: " .. result.original_win)
    print("  Modified buf: " .. result.modified_buf .. " win: " .. result.modified_win)

    vim.defer_fn(function()
      local orig_diff_ok, orig_ft = check_highlights(result.original_buf, "左栏")
      local mod_diff_ok, mod_ft = check_highlights(result.modified_buf, "右栏")
      local ft_ok = (orig_ft == "lua") and (mod_ft == "lua")

      print(string.format("  diff高亮: %s | filetype: %s (orig=%s mod=%s)",
        (orig_diff_ok or mod_diff_ok) and "PASS" or "FAIL",
        ft_ok and "PASS" or "FAIL",
        orig_ft, mod_ft))
      print((orig_diff_ok or mod_diff_ok) and ft_ok and ">>> PASS: diff高亮 + 语法高亮 同时通过" or ">>> FAIL")
    end, 200)
  else
    print("FAIL: view.create error: " .. tostring(result))
  end

  print("  :lua _G.exp02.step()  — 下一步(inline)")
  _G.exp02.step_index = 1
end

-- Step 2: inline 模式验证
function _G.exp02.step2_inline_mode()
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
  vim.api.nvim_buf_set_name(orig_buf, "%:/inline.lua")

  local mod_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(mod_buf, 0, -1, false, mod_lines)
  vim.api.nvim_buf_set_name(mod_buf, "%:/inline.lua/-modified")

  local view = require("codediff.ui.view")
  local ok, result = pcall(view.create, {
    mode = "standalone",
    original_path = "%:/inline.lua",
    modified_path = "%:/inline.lua/-modified",
    layout = "inline",
  }, "lua")

  _G.exp02.cur_tab = vim.api.nvim_get_current_tabpage()

  print("=== Step 2: Inline模式验证 ===")
  if ok then
    local wins = vim.api.nvim_tabpage_list_wins(_G.exp02.cur_tab)
    print(string.format("  view.create PASS (%d windows)", #wins))

    vim.defer_fn(function()
      local diff_ok, ext_ft = check_highlights(result.modified_buf, "inline")
      local ft_ok = (ext_ft == "lua")
      print(string.format("  inline: diff=%s filetype=%s => %s",
        diff_ok and "PASS" or "(none expected)",
        ft_ok and "PASS" or "FAIL",
        ft_ok and ">>> PASS" or ">>> FAIL"))
    end, 200)
  else
    print("FAIL: inline view.create error: " .. tostring(result))
  end

  print("  :lua _G.exp02.step()  — 回到step1")
  _G.exp02.step_index = 2
end

-- Step 切换
function _G.exp02.step()
  if _G.exp02.step_index == 1 then
    _G.exp02.step2_inline_mode()
  elseif _G.exp02.step_index == 2 then
    _G.exp02.step1_side_by_side()
  end
end

-- Summary
function _G.exp02.summary()
  print([[
=== Exp02 验证清单 ===
  1. side-by-side: diff高亮 + filetype语法高亮 同时验证
  2. inline模式: diff高亮 + filetype语法高亮
  :lua _G.exp02.step()      — 循环切换
]])
end

-- === Setup ===
require("codediff").setup()

print("=== Experiment 02: Diff高亮 + Filetype语法高亮 (同时验证) ===")
print("2个验证步骤（side-by-side同时验证/inline模式）")
print("")
_G.exp02.step1_side_by_side()
