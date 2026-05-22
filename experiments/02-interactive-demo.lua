-- Experiment 02 交互式演示版本
-- 运行方式: nvim 然后 :source experiments/02-interactive-demo.lua
-- 保持 diff 视图打开，展示高亮效果

local cwd = vim.fn.getcwd()
vim.opt.rtp:prepend(cwd)
vim.cmd('runtime! plugin/*.lua plugin/*.vim')

local function run()
  require("codediff").setup()

  local original_lines = {
    "function foo()",
    "  local x = 1",
    "  local y = 2",
    "  return x + y",
    "end",
  }

  local modified_lines = {
    "function foo()",
    "  local x = 10   -- changed",
    "  local y = 2",
    "  local z = 3    -- added",
    "  return x + y + z",
    "end",
  }

  local orig_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(orig_buf, 0, -1, false, original_lines)
  -- universe-path 命名：% 表示当前文件，:定位器 指定范围
  vim.api.nvim_buf_set_name(orig_buf, "%:/function foo|end/")

  local mod_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(mod_buf, 0, -1, false, modified_lines)
  vim.api.nvim_buf_set_name(mod_buf, "%:/function foo|end/-modified")

  local view = require("codediff.ui.view")
  local ok, result = pcall(view.create, {
    mode = "standalone",
    original_path = "%:/function foo|end/",
    modified_path = "%:/function foo|end/-modified",
  }, "lua")

  if ok then
    print("=== View created ===")
    print("Original buf:", result.original_buf, "win:", result.original_win)
    print("Modified buf:", result.modified_buf, "win:", result.modified_win)
    print("Check highlighting: green=insert, red=delete")
  else
    print("FAIL:", result)
  end

  vim.cmd("redraw!")
end

run()
-- 不退出，保持用户查看 diff 视图
