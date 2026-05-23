-- Experiment 07 交互式演示：Buffer Writeback (可视化编辑)
-- 运行: nvim 然后 :source experiments/07-interactive-demo.lua
-- 流程：提取区间→在buffer中直接编辑→写回→外部修改被拒绝
-- 使用方法：
--   1. :source experiments/07-interactive-demo.lua  （setup）
--   2. :lua _G.exp07.extract()                      （打开区间buffer）
--   3. 在区间buffer中直接编辑（在nvim中可视修改）
--   4. :lua _G.exp07.writeback()                    （写回并回到原buffer）
--   5. :lua _G.exp07.test_reject()                  （模拟外部修改被拒）

_G.exp07 = {}
_G.exp07.file_state = {}

function _G.exp07.record_state(bufnr)
  _G.exp07.file_state[bufnr] = {
    changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
  }
end

function _G.exp07.file_changed(bufnr)
  local r = _G.exp07.file_state[bufnr]
  if not r then return true end
  if vim.api.nvim_buf_get_changedtick(bufnr) ~= r.changedtick then return true end
  local cur = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #cur ~= #r.lines then return true end
  for i, line in ipairs(cur) do
    if line ~= r.lines[i] then return true end
  end
  return false
end

function _G.exp07.extract_range(src, s, e)
  local lines = vim.api.nvim_buf_get_lines(src, s - 1, e, false)
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_name(buf, string.format("%%:%d-%d", s, e))
  vim.api.nvim_buf_set_var(buf, "up_source", src)
  vim.api.nvim_buf_set_var(buf, "up_start", s)
  vim.api.nvim_buf_set_var(buf, "up_end", e)
  return buf
end

function _G.exp07.do_writeback(range_buf)
  local src = vim.api.nvim_buf_get_var(range_buf, "up_source")
  local s = vim.api.nvim_buf_get_var(range_buf, "up_start")
  local e = vim.api.nvim_buf_get_var(range_buf, "up_end")
  if _G.exp07.file_changed(src) then
    return false, "source file has changed since extraction"
  end
  local new = vim.api.nvim_buf_get_lines(range_buf, 0, -1, false)
  vim.api.nvim_buf_set_lines(src, s - 1, e, false, new)
  _G.exp07.record_state(src)
  local new_end = s + #new - 1
  vim.api.nvim_buf_set_var(range_buf, "up_end", new_end)
  return true, nil
end

-- === Setup ===
local cwd = vim.fn.getcwd()
vim.opt.rtp:prepend(cwd)
vim.cmd('runtime! plugin/*.lua plugin/*.vim')
require("codediff").setup()

_G.exp07.src = vim.api.nvim_create_buf(true, true)
vim.api.nvim_buf_set_lines(_G.exp07.src, 0, -1, false, {
  "function first() {",
  "  return 1;",
  "}",
  "",
  "function second() {",
  "  return 2;",
  "}",
})
vim.api.nvim_buf_set_name(_G.exp07.src, "%")
_G.exp07.record_state(_G.exp07.src)
vim.api.nvim_set_current_buf(_G.exp07.src)

print("=== 原文件buffer: % ===")
print("当前显示的就是原文件内容（2个函数）")
print("")
print(">>> 下一步:")
print("  :lua _G.exp07.extract()        — 提取第一个函数到区间buffer并切换过去")
print("  （在区间buffer中直接编辑，用vim正常操作）")
print("  :lua _G.exp07.writeback()     — 写回原buffer并切换回去看结果")
print("  :lua _G.exp07.test_reject()   — 验证外部修改被拒绝")

-- Step 1: 提取区间并切换到区间buffer
function _G.exp07.extract()
  _G.exp07.rbuf = _G.exp07.extract_range(_G.exp07.src, 1, 3)
  vim.api.nvim_set_current_buf(_G.exp07.rbuf)
  local name = vim.api.nvim_buf_get_name(_G.exp07.rbuf)
  print(string.format(">>> 已切换到区间buffer: %s", name))
  print("现在请直接编辑这个buffer的内容")
end

-- Step 2: 写回并回到原buffer
function _G.exp07.writeback()
  local ok, err = _G.exp07.do_writeback(_G.exp07.rbuf)
  if ok then
    vim.api.nvim_set_current_buf(_G.exp07.src)
    print(">>> 写回SUCCESS，已切回原buffer查看更新结果")
  else
    print(string.format(">>> 写回REJECTED: %s", err))
  end
end

-- Step 3: 外部修改被拒
function _G.exp07.test_reject()
  _G.exp07.record_state(_G.exp07.src)
  local rbuf2 = _G.exp07.extract_range(_G.exp07.src, 4, 5)
  -- 外部修改原文件
  vim.api.nvim_buf_set_lines(_G.exp07.src, 0, 0, false, { "// external mod" })
  print(">>> 模拟: 在原文件顶部插入了 '// external mod'")
  local ok, err = _G.exp07.do_writeback(rbuf2)
  print(string.format(">>> 写回结果: %s", ok and "SUCCESS (unexpected!)" or ("REJECTED: " .. err)))
  vim.api.nvim_set_current_buf(_G.exp07.src)
end
