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
  local name = string.format("%%:%d-%d", s, e)
  local ok = pcall(vim.api.nvim_buf_set_name, buf, name)
  if not ok then
    -- Fallback: try with a unique suffix
    name = string.format("%%:%d-%d-%d", s, e, buf)
    pcall(vim.api.nvim_buf_set_name, buf, name)
  end
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
-- Use unique buffer name to avoid conflict with nvim's special % register
local src_name = "%:exp07-src"
pcall(vim.api.nvim_buf_set_name, _G.exp07.src, src_name)
_G.exp07.record_state(_G.exp07.src)
vim.api.nvim_set_current_buf(_G.exp07.src)

print("=== 原文件buffer: " .. src_name .. " ===")
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

-- === Line Number Change Re-location Precision Tests ===
-- 测试行数变化后的区间重新定位精确性
-- 运行:
--   :lua _G.exp07.test_line_relocation()  — 运行全部行数变化重定位测试
--   或单独运行:
--   :lua _G.exp07.test_add_lines()
--   :lua _G.exp07.test_delete_lines()
--   :lua _G.exp07.test_total_rewrite()
--   :lua _G.exp07.test_shrink_to_one_line()
--   :lua _G.exp07.test_re_extract_after_writeback()

function _G.exp07.reset_test()
  -- Reset source buffer to known initial state and record baseline
  vim.api.nvim_buf_set_lines(_G.exp07.src, 0, -1, false, {
    "function first() {",
    "  return 1;",
    "}",
    "",
    "function second() {",
    "  return 2;",
    "}",
  })
  _G.exp07.record_state(_G.exp07.src)
  print(">>> Test buffer reset to initial state (7 lines)")
end

function _G.exp07.test_add_lines()
  -- Scenario: extract block (1-3), ADD 2 lines, writeback -> end shifts +2
  _G.exp07.reset_test()

  local rbuf = _G.exp07.extract_range(_G.exp07.src, 1, 3)
  local orig_start = vim.api.nvim_buf_get_var(rbuf, "up_start")
  local orig_end = vim.api.nvim_buf_get_var(rbuf, "up_end")
  assert(orig_start == 1 and orig_end == 3,
    string.format("extract_range start/end mismatch: %d-%d", orig_start, orig_end))

  -- Add 2 lines after line 2 (0-indexed: position 2)
  vim.api.nvim_buf_set_lines(rbuf, 2, 2, false, {
    "  local x = 0;",
    "  print(x);",
  })

  local ok, err = _G.exp07.do_writeback(rbuf)
  local new_end = vim.api.nvim_buf_get_var(rbuf, "up_end")

  -- new_end should be: start + num_lines - 1 = 1 + 5 - 1 = 5
  local expected_end = 5
  local pass = ok and (new_end == expected_end)

  print(string.format("test_add_lines: %s (writeback_ok=%s, expected_end=%d, actual_end=%d)",
    pass and "PASS" or "FAIL", tostring(ok), expected_end, new_end))

  -- Verify source content
  local src = vim.api.nvim_buf_get_lines(_G.exp07.src, 0, -1, false)
  assert(#src == 9, string.format("expected 9 source lines, got %d", #src))
  assert(src[1] == "function first() {", "line 1 mismatch")
  assert(src[5] == "}", "line 5 mismatch (original line 3 shifted down by 2)")
  assert(src[6] == "", "line 6 mismatch (original line 4 shifted down by 2)")

  print("  Verified: source[1..5] = edited block, source[6..9] = original trailing lines")
  vim.api.nvim_buf_delete(rbuf, { force = true })
  return pass
end

function _G.exp07.test_delete_lines()
  -- Scenario: extract block (1-3), DELETE 1 line, writeback -> end shifts -1
  _G.exp07.reset_test()

  local rbuf = _G.exp07.extract_range(_G.exp07.src, 1, 3)

  -- Delete line 2 ("  return 1;"), 0-indexed position 1 to 2
  vim.api.nvim_buf_set_lines(rbuf, 1, 2, false, {})

  local ok, err = _G.exp07.do_writeback(rbuf)
  local new_end = vim.api.nvim_buf_get_var(rbuf, "up_end")

  -- new_end should be: start + num_lines - 1 = 1 + 2 - 1 = 2
  local expected_end = 2
  local pass = ok and (new_end == expected_end)

  print(string.format("test_delete_lines: %s (writeback_ok=%s, expected_end=%d, actual_end=%d)",
    pass and "PASS" or "FAIL", tostring(ok), expected_end, new_end))

  -- Verify source content: block reduced from 3 to 2 lines, total from 7 to 6
  local src = vim.api.nvim_buf_get_lines(_G.exp07.src, 0, -1, false)
  assert(#src == 6, string.format("expected 6 source lines, got %d", #src))
  assert(src[1] == "function first() {", "line 1 mismatch")
  assert(src[2] == "}", "line 2 mismatch (should be original line 3 shifted up)")
  assert(src[3] == "", "line 3 mismatch (should be original line 4 shifted up)")

  print("  Verified: source[1..2] = edited block, source[3..6] = original trailing lines")
  vim.api.nvim_buf_delete(rbuf, { force = true })
  return pass
end

function _G.exp07.test_total_rewrite()
  -- Scenario: extract block (1-3, 3 lines), replace with 4 different lines -> end recalculated
  _G.exp07.reset_test()

  local rbuf = _G.exp07.extract_range(_G.exp07.src, 1, 3)

  -- Replace entire block content with 4 different lines
  vim.api.nvim_buf_set_lines(rbuf, 0, -1, false, {
    "function rewritten(a, b) {",
    "  local c = a + b;",
    "  return c * 2;",
    "}",
  })

  local ok, err = _G.exp07.do_writeback(rbuf)
  local new_start = vim.api.nvim_buf_get_var(rbuf, "up_start")
  local new_end = vim.api.nvim_buf_get_var(rbuf, "up_end")

  -- new_end should be: 1 + 4 - 1 = 4
  local expected_end = 4
  local pass = ok and (new_start == 1) and (new_end == expected_end)

  print(string.format("test_total_rewrite: %s (writeback_ok=%s, range=%d-%d, expected=%d-%d)",
    pass and "PASS" or "FAIL", tostring(ok), new_start, new_end, 1, expected_end))

  -- Verify source content: total lines = 7 - 3 + 4 = 8
  local src = vim.api.nvim_buf_get_lines(_G.exp07.src, 0, -1, false)
  assert(#src == 8, string.format("expected 8 source lines, got %d", #src))
  assert(src[1] == "function rewritten(a, b) {", "line 1 mismatch")
  assert(src[4] == "}", "line 4 mismatch (end of rewritten block)")
  assert(src[5] == "", "line 5 mismatch (original empty line)")
  assert(src[6] == "function second() {", "line 6 mismatch (second function)")

  print("  Verified: source[1..4] = rewritten block, source[5..8] = original trailing lines")
  vim.api.nvim_buf_delete(rbuf, { force = true })
  return pass
end

function _G.exp07.test_shrink_to_one_line()
  -- Scenario: extract block (1-3, 3 lines), shrink to 1 line -> end == start
  _G.exp07.reset_test()

  local rbuf = _G.exp07.extract_range(_G.exp07.src, 1, 3)

  -- Replace 3-line block with a single-line placeholder
  vim.api.nvim_buf_set_lines(rbuf, 0, -1, false, {
    "-- function first() removed in refactor",
  })

  local ok, err = _G.exp07.do_writeback(rbuf)
  local new_start = vim.api.nvim_buf_get_var(rbuf, "up_start")
  local new_end = vim.api.nvim_buf_get_var(rbuf, "up_end")

  -- new_end should be: 1 + 1 - 1 = 1 (end == start, single-line block)
  local pass = ok and (new_start == 1) and (new_end == 1)

  print(string.format("test_shrink_to_one_line: %s (writeback_ok=%s, range=%d-%d)",
    pass and "PASS" or "FAIL", tostring(ok), new_start, new_end))

  -- Verify source: original 7 lines, block went from 3 to 1 -> total 5
  local src = vim.api.nvim_buf_get_lines(_G.exp07.src, 0, -1, false)
  assert(#src == 5, string.format("expected 5 source lines, got %d", #src))
  assert(src[1] == "-- function first() removed in refactor", "line 1 mismatch (shrunk block)")
  assert(src[2] == "", "line 2 mismatch (original line 4 shifted up by 2)")
  assert(src[3] == "function second() {", "line 3 mismatch (original line 5 shifted up by 2)")

  print("  Verified: source[1] = 1-line block, source[2..5] = original trailing lines shifted up")
  vim.api.nvim_buf_delete(rbuf, { force = true })
  return pass
end

function _G.exp07.test_re_extract_after_writeback()
  -- Scenario: write back modified block, then re-extract using updated range -> content matches
  _G.exp07.reset_test()

  local rbuf = _G.exp07.extract_range(_G.exp07.src, 1, 3)

  -- Add a line at the end of the block
  vim.api.nvim_buf_set_lines(rbuf, 3, 3, false, {
    "  local helper = function() return 42; end;",
  })

  local ok, err = _G.exp07.do_writeback(rbuf)
  assert(ok, "writeback failed: " .. (err or "nil"))

  local new_start = vim.api.nvim_buf_get_var(rbuf, "up_start")
  local new_end = vim.api.nvim_buf_get_var(rbuf, "up_end")
  -- new_end should be: 1 + 4 - 1 = 4
  assert(new_end == 4, string.format("expected new_end=4, got %d", new_end))

  -- Re-extract using the updated range
  _G.exp07.record_state(_G.exp07.src)
  local rbuf2 = _G.exp07.extract_range(_G.exp07.src, new_start, new_end)
  local re_extracted = vim.api.nvim_buf_get_lines(rbuf2, 0, -1, false)

  local pass = (#re_extracted == 4)
    and (re_extracted[1] == "function first() {")
    and (re_extracted[2] == "  return 1;")
    and (re_extracted[3] == "}")
    and (re_extracted[4] == "  local helper = function() return 42; end;")

  print(string.format("test_re_extract_after_writeback: %s (range=%d-%d, re_extracted_lines=%d)",
    pass and "PASS" or "FAIL", new_start, new_end, #re_extracted))

  if not pass then
    print("  Expected: 4 lines matching written content")
    print("  Actual:")
    for i, l in ipairs(re_extracted) do
      print(string.format("    [%d] %s", i, l))
    end
  else
    print("  Verified: re-extracted content matches written-back content")
  end

  vim.api.nvim_buf_delete(rbuf, { force = true })
  vim.api.nvim_buf_delete(rbuf2, { force = true })
  return pass
end

function _G.exp07.test_line_relocation()
  -- Batch runner: execute all line-number re-location precision tests
  print("")
  print("============================================================")
  print("  Line Number Change Re-location Precision Tests")
  print("============================================================")
  print("")

  local results = {}
  local all_pass = true

  local tests = {
    { name = "test_add_lines", fn = _G.exp07.test_add_lines },
    { name = "test_delete_lines", fn = _G.exp07.test_delete_lines },
    { name = "test_total_rewrite", fn = _G.exp07.test_total_rewrite },
    { name = "test_shrink_to_one_line", fn = _G.exp07.test_shrink_to_one_line },
    { name = "test_re_extract_after_writeback", fn = _G.exp07.test_re_extract_after_writeback },
  }

  for _, t in ipairs(tests) do
    local ok, result = pcall(t.fn)
    if not ok then
      print(string.format("  %s: ERROR - %s", t.name, tostring(result)))
      table.insert(results, { name = t.name, pass = false, error = result })
      all_pass = false
    else
      table.insert(results, { name = t.name, pass = result, error = nil })
      if not result then all_pass = false end
    end
    print("")
  end

  print("------------------------------------------------------------")
  print("  Summary:")
  for _, r in ipairs(results) do
    local status = r.pass and "PASS" or "FAIL"
    local suffix = r.error and (" (" .. tostring(r.error) .. ")") or ""
    print(string.format("    %s: %s%s", r.name, status, suffix))
  end
  print("------------------------------------------------------------")
  print(string.format("  Overall: %s", all_pass and "ALL PASS" or "SOME FAILED"))
  print("============================================================")

  -- Restore test buffer to known state
  _G.exp07.reset_test()
  return all_pass
end
