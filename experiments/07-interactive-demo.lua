-- Experiment 07 交互式演示：Buffer Writeback
-- 运行: nvim 然后 :source experiments/07-interactive-demo.lua
-- 验证：提取区间→编辑→写回→原文件更新 + 原文件有变动则拒绝写回
-- 使用方法：source 脚本后，依次执行：
--   :lua _G.exp07.step1()
--   :lua _G.exp07.step2()
--   :lua _G.exp07.step3()
--   :lua _G.exp07.step4()

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

function _G.exp07.writeback(range_buf)
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

-- === Setup: 创建原文件buffer ===
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

print("=== 原文件buffer: % 已创建 ===")
print("内容: 两个function块")
for _, line in ipairs(vim.api.nvim_buf_get_lines(_G.exp07.src, 0, -1, false)) do
  print("  " .. line)
end
print("")
print(">>> 现在逐步执行:")
print("  :lua _G.exp07.step1()  — 提取区间")
print("  :lua _G.exp07.step2()  — 修改区间")
print("  :lua _G.exp07.step3()  — 写回")
print("  :lua _G.exp07.step4()  — 验证外部修改拒绝")

-- Step 1: 提取区间 (lines 1-3, the first function)
function _G.exp07.step1()
  print("")
  print(">>> Step 1: 提取区间 1-3 (first function)")
  _G.exp07.rbuf = _G.exp07.extract_range(_G.exp07.src, 1, 3)
  local rname = vim.api.nvim_buf_get_name(_G.exp07.rbuf)
  print(string.format("提取到 range buffer: %s", rname))
  print("区间内容:")
  for _, line in ipairs(vim.api.nvim_buf_get_lines(_G.exp07.rbuf, 0, -1, false)) do
    print("  " .. line)
  end
end

-- Step 2: 修改区间buffer
function _G.exp07.step2()
  print("")
  print(">>> Step 2: 修改区间buffer (return 1 -> return 100)")
  vim.api.nvim_buf_set_lines(_G.exp07.rbuf, 0, -1, false, {
    "function first() {",
    "  return 100;",
    "}",
  })
  print("修改后:")
  for _, line in ipairs(vim.api.nvim_buf_get_lines(_G.exp07.rbuf, 0, -1, false)) do
    print("  " .. line)
  end
end

-- Step 3: 写回
function _G.exp07.step3()
  print("")
  print(">>> Step 3: 写回原buffer")
  local ok, err = _G.exp07.writeback(_G.exp07.rbuf)
  print(string.format("写回结果: %s", ok and "SUCCESS" or ("FAIL: " .. err)))
  print("原文件buffer更新后:")
  for _, line in ipairs(vim.api.nvim_buf_get_lines(_G.exp07.src, 0, -1, false)) do
    print("  " .. line)
  end
end

-- Step 4: 模拟外部修改 + 写回拒绝
function _G.exp07.step4()
  print("")
  print(">>> Step 4: 模拟外部修改，验证写回拒绝")
  _G.exp07.record_state(_G.exp07.src)
  local rbuf2 = _G.exp07.extract_range(_G.exp07.src, 4, 5)
  print(string.format("提取第二个区间: %s", vim.api.nvim_buf_get_name(rbuf2)))
  -- 外部修改原文件
  vim.api.nvim_buf_set_lines(_G.exp07.src, 0, 0, false, { "// external mod" })
  print("模拟外部修改: 在原文件第1行插入 '// external mod'")
  local ok, err = _G.exp07.writeback(rbuf2)
  print(string.format("写回结果: %s", ok and "SUCCESS (unexpected!)" or ("REJECTED: " .. err)))
end
