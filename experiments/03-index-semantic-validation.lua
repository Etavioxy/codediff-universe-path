-- Experiment 03: Index Semantic Validation
-- 验证嵌套{}下索引正确性及倒序[-N]反向扫描
--
-- 测试环境：
-- 1. 正常环境：括号匹配正常，验证正向/倒序索引
-- 2. 失配环境：括号失配，验证错误检测

-- 运行方式：nvim -l experiments/03-index-semantic-validation.lua

local M = {}

--- 嵌套匹配（带失配检测）
---@param lines string[]
---@param start_delim string
---@param end_delim string
---@param index number
---@return number|nil start_line, number|nil end_line, string|nil error
function M.nested_match(lines, start_delim, end_delim, index)
  index = index or 0
  local count = 0
  local nesting = 0
  local start_line = nil
  local first_unclosed = nil

  for i, line in ipairs(lines) do
    for j = 1, #line do
      local char = line:sub(j, j)
      if char == start_delim then
        if nesting == 0 then
          count = count + 1
          if count == index + 1 then
            start_line = i
          end
        end
        first_unclosed = first_unclosed or { line = i, col = j }
        nesting = nesting + 1
      elseif char == end_delim then
        nesting = nesting - 1
        if nesting < 0 then
          return nil, nil, "unmatched closing delimiter at line " .. i
        end
        if nesting == 0 then
          first_unclosed = nil
          if start_line then
            return start_line, i, nil
          end
        end
      end
    end
  end

  if nesting > 0 then
    return nil, nil, "unclosed delimiter starting at line " .. (first_unclosed and first_unclosed.line or "?")
  end

  return nil, nil, "index out of range"
end

--- 反向扫描：从文件末尾开始找第N个块（-1表示最后一个）
function M.reverse_nested_match(lines, start_delim, end_delim, reverse_index)
  local target_index = reverse_index * -1
  local blocks = {}
  local nesting = 0
  local current_start = nil
  local current_start_line = nil

  for i, line in ipairs(lines) do
    for j = 1, #line do
      local char = line:sub(j, j)
      if char == start_delim then
        if nesting == 0 then
          current_start_line = i
          current_start = #blocks + 1
        end
        nesting = nesting + 1
      elseif char == end_delim then
        nesting = nesting - 1
        if nesting == 0 and current_start_line then
          blocks[current_start] = { start_line = current_start_line, end_line = i }
          current_start_line = nil
        end
      end
    end
  end

  if target_index > #blocks then
    return nil, nil
  end

  local block = blocks[#blocks - target_index + 1]
  return block and block.start_line, block and block.end_line
end

-- ============================================
-- 测试环境1：正常环境
-- ============================================

print("============================================")
print("测试环境1：正常环境")
print("============================================")

local test_code = {
  "function first() {     -- 1",
  "  // first block",
  "}                      -- 3",
  "function second() {    -- 4",
  "  function inner() {   -- 5",
  "  }                    -- 6",
  "}                      -- 7",
  "function third() {     -- 8",
  "}                      -- 9",
}

print("\n=== 正向索引测试 ===")
local s1, e1, err1 = M.nested_match(test_code, "{", "}", 0)
print(string.format("[0] 第1个块: 行%d-%d (期望: 1-3)", s1 or 0, e1 or 0))

local s2, e2, err2 = M.nested_match(test_code, "{", "}", 1)
print(string.format("[1] 第2个块: 行%d-%d (期望: 4-7)", s2 or 0, e2 or 0))

local s3, e3, err3 = M.nested_match(test_code, "{", "}", 2)
print(string.format("[2] 第3个块: 行%d-%d (期望: 8-9)", s3 or 0, e3 or 0))

print("\n=== 倒序索引测试 ===")
local s4, e4 = M.reverse_nested_match(test_code, "{", "}", -1)
print(string.format("[-1] 最后一个块: 行%d-%d (期望: 8-9)", s4 or 0, e4 or 0))

local s5, e5 = M.reverse_nested_match(test_code, "{", "}", -2)
print(string.format("[-2] 倒数第二个块: 行%d-%d (期望: 4-7)", s5 or 0, e5 or 0))

local s6, e6 = M.reverse_nested_match(test_code, "{", "}", -3)
print(string.format("[-3] 倒数第三个块: 行%d-%d (期望: 1-3)", s6 or 0, e6 or 0))

print("\n=== 验证结果 ===")
local pass = true

if s1 ~= 1 or e1 ~= 3 then pass = false; print("FAIL: [0] 不匹配") end
if s2 ~= 4 or e2 ~= 7 then pass = false; print("FAIL: [1] 不匹配") end
if s3 ~= 8 or e3 ~= 9 then pass = false; print("FAIL: [2] 不匹配") end
if s4 ~= 8 or e4 ~= 9 then pass = false; print("FAIL: [-1] 不匹配") end
if s5 ~= 4 or e5 ~= 7 then pass = false; print("FAIL: [-2] 不匹配") end
if s6 ~= 1 or e6 ~= 3 then pass = false; print("FAIL: [-3] 不匹配") end

if pass then
  print("PASS: 所有索引测试通过")
end

-- ============================================
-- 测试环境2：失配环境
-- ============================================

print("\n============================================")
print("测试环境2：失配环境")
print("============================================")

print("\n=== 未闭合 { 测试 ===")
local unclosed_code = {
  "function foo() {",
  "  function inner() {",
  "}",
}
local u1, u2, err4 = M.nested_match(unclosed_code, "{", "}", 0)
print(string.format("结果: 行%d-%d, 错误: %s", u1 or 0, u2 or 0, err4 or "nil"))

print("\n=== 多余 } 测试 ===")
local extra_close_code = {
  "}",
  "function foo() {",
  "}",
}
local e1, e2, err5 = M.nested_match(extra_close_code, "{", "}", 0)
print(string.format("结果: 行%d-%d, 错误: %s", e1 or 0, e2 or 0, err5 or "nil"))

print("\n=== 验证失配检测 ===")
if err4 == nil then print("FAIL: 未闭合应报错") end
if err5 == nil then print("FAIL: 多余}应报错") end

if err4 and err5 then
  print("PASS: 失配检测正确")
end

-- ============================================
-- 测试环境3：复杂跨行嵌套 — 填补文档缺口
-- ============================================

print("\n============================================")
print("测试环境3：复杂跨行嵌套")
print("============================================")

---
-- 3.1 多种分隔符类型的跨行交叉嵌套
-- 模拟 {a(b[c]d)e} 风格，不同类型分隔符在跨行时相互交错
---
local cross_nested_code = {
	"function dispatch() {              --  1",
	"  if (status == 'ok') {            --  2",
	"    items[idx] = task(name)        --  3",
	"  }                                --  4",
	"  for (k, v in pairs(map)) {       --  5",
	"    local x = data[k]              --  6",
	"    callback(x)                    --  7",
	"  }                                --  8",
	"}                                  --  9",
}

print("\n--- 3.1 交叉嵌套: {} 正向索引 ---")
local cx_s1, cx_e1 = M.nested_match(cross_nested_code, "{", "}", 0)
print(string.format("[0] 第1个{}块: 行%d-%d (期望: 1-9)", cx_s1 or 0, cx_e1 or 0))

local cx_s2, cx_e2 = M.nested_match(cross_nested_code, "{", "}", 1)
print(string.format("[1] 第2个{}块: 行%d-%d (期望: 2-4)", cx_s2 or 0, cx_e2 or 0))

local cx_s3, cx_e3 = M.nested_match(cross_nested_code, "{", "}", 2)
print(string.format("[2] 第3个{}块: 行%d-%d (期望: 5-8)", cx_s3 or 0, cx_e3 or 0))

print("\n--- 3.1 交叉嵌套: {} 倒序索引 ---")
local cx_r1, cx_f1 = M.reverse_nested_match(cross_nested_code, "{", "}", -1)
print(string.format("[-1] 最后一个{}块: 行%d-%d (期望: 5-8)", cx_r1 or 0, cx_f1 or 0))

local cx_r2, cx_f2 = M.reverse_nested_match(cross_nested_code, "{", "}", -2)
print(string.format("[-2] 倒数第2个{}块: 行%d-%d (期望: 2-4)", cx_r2 or 0, cx_f2 or 0))

local cx_r3, cx_f3 = M.reverse_nested_match(cross_nested_code, "{", "}", -3)
print(string.format("[-3] 倒数第3个{}块: 行%d-%d (期望: 1-9)", cx_r3 or 0, cx_f3 or 0))

print("\n--- 3.1 交叉嵌套: () 正向索引 (跨行+内部有{}) ---")
local cx_p1, cx_q1 = M.nested_match(cross_nested_code, "(", ")", 0)
print(string.format("[0] 第1个()块: 行%d-%d (期望: 2-2)", cx_p1 or 0, cx_q1 or 0))

local cx_p2, cx_q2 = M.nested_match(cross_nested_code, "(", ")", 1)
print(string.format("[1] 第2个()块: 行%d-%d (期望: 3-3)", cx_p2 or 0, cx_q2 or 0))

local cx_p3, cx_q3 = M.nested_match(cross_nested_code, "(", ")", 2)
print(string.format("[2] 第3个()块: 行%d-%d (期望: 5-5)", cx_p3 or 0, cx_q3 or 0))

local cx_p4, cx_q4 = M.nested_match(cross_nested_code, "(", ")", 3)
print(string.format("[3] 第4个()块: 行%d-%d (期望: 7-7)", cx_p4 or 0, cx_q4 or 0))

print("\n--- 3.1 交叉嵌套: () 倒序索引 ---")
local cx_rp1, cx_fp1 = M.reverse_nested_match(cross_nested_code, "(", ")", -1)
print(string.format("[-1] 最后一个()块: 行%d-%d (期望: 7-7)", cx_rp1 or 0, cx_fp1 or 0))

local cx_rp2, cx_fp2 = M.reverse_nested_match(cross_nested_code, "(", ")", -2)
print(string.format("[-2] 倒数第2个()块: 行%d-%d (期望: 5-5)", cx_rp2 or 0, cx_fp2 or 0))

print("\n--- 3.1 交叉嵌套: [] 正向索引 ---")
local cx_sb1, cx_eb1 = M.nested_match(cross_nested_code, "[", "]", 0)
print(string.format("[0] 第1个[]块: 行%d-%d (期望: 3-3)", cx_sb1 or 0, cx_eb1 or 0))

local cx_sb2, cx_eb2 = M.nested_match(cross_nested_code, "[", "]", 1)
print(string.format("[1] 第2个[]块: 行%d-%d (期望: 6-6)", cx_sb2 or 0, cx_eb2 or 0))

print("\n--- 3.1 交叉嵌套: [] 倒序索引 ---")
local cx_rs1, cx_fe1 = M.reverse_nested_match(cross_nested_code, "[", "]", -1)
print(string.format("[-1] 最后一个[]块: 行%d-%d (期望: 6-6)", cx_rs1 or 0, cx_fe1 or 0))

local cx_rs2, cx_fe2 = M.reverse_nested_match(cross_nested_code, "[", "]", -2)
print(string.format("[-2] 倒数第2个[]块: 行%d-%d (期望: 3-3)", cx_rs2 or 0, cx_fe2 or 0))

---
-- 3.2 不同缩进级别上的混合分隔符深度嵌套
-- 模拟跨越许多行的多层嵌套块，配合各种缩进
---
local deep_nested_code = {
	"module M {                         --  1",
	"  class Factory {                  --  2",
	"    static create(opts) {          --  3",
	"      local t = type(opts)         --  4",
	"      if (t == 'table') {          --  5",
	"        local keys = {}            --  6",
	"        for (i, k in ipairs(opts)) { --  7",
	"          keys[i] = k              --  8",
	"        }                          --  9",
	"        local seen = {}            -- 10",
	"        for (j, v in pairs(opts)) { -- 11",
	"          seen[j] = transform(v)   -- 12",
	"        }                          -- 13",
	"        return build(keys, seen)   -- 14",
	"      }                            -- 15",
	"      return nil                   -- 16",
	"    }                              -- 17",
	"  }                                -- 18",
	"}                                  -- 19",
}

print("\n--- 3.2 深度嵌套: {} 正向索引 ---")
local dp_s1, dp_e1 = M.nested_match(deep_nested_code, "{", "}", 0)
print(string.format("[0] 第1个{}块: 行%d-%d (期望: 1-19)", dp_s1 or 0, dp_e1 or 0))

local dp_s2, dp_e2 = M.nested_match(deep_nested_code, "{", "}", 1)
print(string.format("[1] 第2个{}块: 行%d-%d (期望: 2-18)", dp_s2 or 0, dp_e2 or 0))

local dp_s3, dp_e3 = M.nested_match(deep_nested_code, "{", "}", 2)
print(string.format("[2] 第3个{}块: 行%d-%d (期望: 3-17)", dp_s3 or 0, dp_e3 or 0))

local dp_s4, dp_e4 = M.nested_match(deep_nested_code, "{", "}", 3)
print(string.format("[3] 第4个{}块: 行%d-%d (期望: 5-15)", dp_s4 or 0, dp_e4 or 0))

local dp_s5, dp_e5 = M.nested_match(deep_nested_code, "{", "}", 4)
print(string.format("[4] 第5个{}块: 行%d-%d (期望: 6-6)", dp_s5 or 0, dp_e5 or 0))

local dp_s6, dp_e6 = M.nested_match(deep_nested_code, "{", "}", 5)
print(string.format("[5] 第6个{}块: 行%d-%d (期望: 7-9)", dp_s6 or 0, dp_e6 or 0))

local dp_s7, dp_e7 = M.nested_match(deep_nested_code, "{", "}", 6)
print(string.format("[6] 第7个{}块: 行%d-%d (期望: 10-10)", dp_s7 or 0, dp_e7 or 0))

local dp_s8, dp_e8 = M.nested_match(deep_nested_code, "{", "}", 7)
print(string.format("[7] 第8个{}块: 行%d-%d (期望: 11-13)", dp_s8 or 0, dp_e8 or 0))

print("\n--- 3.2 深度嵌套: {} 倒序索引 ---")
local dp_r1, dp_f1 = M.reverse_nested_match(deep_nested_code, "{", "}", -1)
print(string.format("[-1] 最后一个{}块: 行%d-%d (期望: 11-13)", dp_r1 or 0, dp_f1 or 0))

local dp_r2, dp_f2 = M.reverse_nested_match(deep_nested_code, "{", "}", -2)
print(string.format("[-2] 倒数第2个{}块: 行%d-%d (期望: 10-10)", dp_r2 or 0, dp_f2 or 0))

local dp_r3, dp_f3 = M.reverse_nested_match(deep_nested_code, "{", "}", -3)
print(string.format("[-3] 倒数第3个{}块: 行%d-%d (期望: 7-9)", dp_r3 or 0, dp_f3 or 0))

local dp_r4, dp_f4 = M.reverse_nested_match(deep_nested_code, "{", "}", -4)
print(string.format("[-4] 倒数第4个{}块: 行%d-%d (期望: 6-6)", dp_r4 or 0, dp_f4 or 0))

local dp_r5, dp_f5 = M.reverse_nested_match(deep_nested_code, "{", "}", -5)
print(string.format("[-5] 倒数第5个{}块: 行%d-%d (期望: 5-15)", dp_r5 or 0, dp_f5 or 0))

local dp_r6, dp_f6 = M.reverse_nested_match(deep_nested_code, "{", "}", -6)
print(string.format("[-6] 倒数第6个{}块: 行%d-%d (期望: 3-17)", dp_r6 or 0, dp_f6 or 0))

local dp_r7, dp_f7 = M.reverse_nested_match(deep_nested_code, "{", "}", -7)
print(string.format("[-7] 倒数第7个{}块: 行%d-%d (期望: 2-18)", dp_r7 or 0, dp_f7 or 0))

local dp_r8, dp_f8 = M.reverse_nested_match(deep_nested_code, "{", "}", -8)
print(string.format("[-8] 倒数第8个{}块: 行%d-%d (期望: 1-19)", dp_r8 or 0, dp_f8 or 0))

print("\n--- 3.2 深度嵌套: () 正向索引 (深层混合) ---")
local dp_p1, dp_q1 = M.nested_match(deep_nested_code, "(", ")", 0)
print(string.format("[0] 第1个()块: 行%d-%d (期望: 3-3)", dp_p1 or 0, dp_q1 or 0))

local dp_p2, dp_q2 = M.nested_match(deep_nested_code, "(", ")", 1)
print(string.format("[1] 第2个()块: 行%d-%d (期望: 4-4)", dp_p2 or 0, dp_q2 or 0))

local dp_p3, dp_q3 = M.nested_match(deep_nested_code, "(", ")", 2)
print(string.format("[2] 第3个()块: 行%d-%d (期望: 7-7)", dp_p3 or 0, dp_q3 or 0))

local dp_p4, dp_q4 = M.nested_match(deep_nested_code, "(", ")", 3)
print(string.format("[3] 第4个()块: 行%d-%d (期望: 11-11)", dp_p4 or 0, dp_q4 or 0))

local dp_p5, dp_q5 = M.nested_match(deep_nested_code, "(", ")", 4)
print(string.format("[4] 第5个()块: 行%d-%d (期望: 12-12)", dp_p5 or 0, dp_q5 or 0))

local dp_p6, dp_q6 = M.nested_match(deep_nested_code, "(", ")", 5)
print(string.format("[5] 第6个()块: 行%d-%d (期望: 14-14)", dp_p6 or 0, dp_q6 or 0))

print("\n--- 3.2 深度嵌套: () 倒序索引 ---")
local dp_rp1, dp_fp1 = M.reverse_nested_match(deep_nested_code, "(", ")", -1)
print(string.format("[-1] 最后一个()块: 行%d-%d (期望: 14-14)", dp_rp1 or 0, dp_fp1 or 0))

local dp_rp2, dp_fp2 = M.reverse_nested_match(deep_nested_code, "(", ")", -2)
print(string.format("[-2] 倒数第2个()块: 行%d-%d (期望: 12-12)", dp_rp2 or 0, dp_fp2 or 0))

local dp_rp3, dp_fp3 = M.reverse_nested_match(deep_nested_code, "(", ")", -3)
print(string.format("[-3] 倒数第3个()块: 行%d-%d (期望: 11-11)", dp_rp3 or 0, dp_fp3 or 0))

---
-- 3.3 边界情况：多行嵌套后同一行连续闭合
-- 模拟 function a() { function b() { function c() { } }} 风格
---
local consecutive_close_code = {
	"class Pipeline {                   --  1",
	"  method init(self) {              --  2",
	"    self.stages = {}               --  3",
	"    setup(self)                    --  4",
	"    local a = func_a()             --  5",
	"    if (a.ok) {                    --  6",
	"      init_stage(a.data)           --  7",
	"    }                              --  8",
	"    return self                    --  9",
	"  }}                               -- 10  <- 两个}在同一行,闭合method和class",
}

print("\n--- 3.3 连续闭合: {} 正向索引 ---")
local cc_s1, cc_e1 = M.nested_match(consecutive_close_code, "{", "}", 0)
print(string.format("[0] 第1个{}块: 行%d-%d (期望: 1-10)", cc_s1 or 0, cc_e1 or 0))

local cc_s2, cc_e2 = M.nested_match(consecutive_close_code, "{", "}", 1)
print(string.format("[1] 第2个{}块: 行%d-%d (期望: 2-10)", cc_s2 or 0, cc_e2 or 0))

local cc_s3, cc_e3 = M.nested_match(consecutive_close_code, "{", "}", 2)
print(string.format("[2] 第3个{}块: 行%d-%d (期望: 3-3)", cc_s3 or 0, cc_e3 or 0))

local cc_s4, cc_e4 = M.nested_match(consecutive_close_code, "{", "}", 3)
print(string.format("[3] 第4个{}块: 行%d-%d (期望: 6-8)", cc_s4 or 0, cc_e4 or 0))

print("\n--- 3.3 连续闭合: {} 倒序索引 ---")
local cc_r1, cc_f1 = M.reverse_nested_match(consecutive_close_code, "{", "}", -1)
print(string.format("[-1] 最后一个{}块: 行%d-%d (期望: 6-8)", cc_r1 or 0, cc_f1 or 0))

local cc_r2, cc_f2 = M.reverse_nested_match(consecutive_close_code, "{", "}", -2)
print(string.format("[-2] 倒数第2个{}块: 行%d-%d (期望: 3-3)", cc_r2 or 0, cc_f2 or 0))

local cc_r3, cc_f3 = M.reverse_nested_match(consecutive_close_code, "{", "}", -3)
print(string.format("[-3] 倒数第3个{}块: 行%d-%d (期望: 2-10)", cc_r3 or 0, cc_f3 or 0))

local cc_r4, cc_f4 = M.reverse_nested_match(consecutive_close_code, "{", "}", -4)
print(string.format("[-4] 倒数第4个{}块: 行%d-%d (期望: 1-10)", cc_r4 or 0, cc_f4 or 0))

print("\n--- 3.3 连续闭合: () 正向索引 ---")
local cc_p1, cc_q1 = M.nested_match(consecutive_close_code, "(", ")", 0)
print(string.format("[0] 第1个()块: 行%d-%d (期望: 2-2)", cc_p1 or 0, cc_q1 or 0))

local cc_p2, cc_q2 = M.nested_match(consecutive_close_code, "(", ")", 1)
print(string.format("[1] 第2个()块: 行%d-%d (期望: 4-4)", cc_p2 or 0, cc_q2 or 0))

local cc_p3, cc_q3 = M.nested_match(consecutive_close_code, "(", ")", 2)
print(string.format("[2] 第3个()块: 行%d-%d (期望: 5-5)", cc_p3 or 0, cc_q3 or 0))

local cc_p4, cc_q4 = M.nested_match(consecutive_close_code, "(", ")", 3)
print(string.format("[3] 第4个()块: 行%d-%d (期望: 6-6)", cc_p4 or 0, cc_q4 or 0))

local cc_p5, cc_q5 = M.nested_match(consecutive_close_code, "(", ")", 4)
print(string.format("[4] 第5个()块: 行%d-%d (期望: 7-7)", cc_p5 or 0, cc_q5 or 0))

print("\n--- 3.3 连续闭合: () 倒序索引 ---")
local cc_rp1, cc_fp1 = M.reverse_nested_match(consecutive_close_code, "(", ")", -1)
print(string.format("[-1] 最后一个()块: 行%d-%d (期望: 7-7)", cc_rp1 or 0, cc_fp1 or 0))

local cc_rp2, cc_fp2 = M.reverse_nested_match(consecutive_close_code, "(", ")", -2)
print(string.format("[-2] 倒数第2个()块: 行%d-%d (期望: 6-6)", cc_rp2 or 0, cc_fp2 or 0))

local cc_rp3, cc_fp3 = M.reverse_nested_match(consecutive_close_code, "(", ")", -3)
print(string.format("[-3] 倒数第3个()块: 行%d-%d (期望: 5-5)", cc_rp3 or 0, cc_fp3 or 0))

-- ============================================
-- 测试环境3 验证汇总
-- ============================================

print("\n============================================")
print("验证汇总：测试环境3")
print("============================================")

local pass3_total = 0
local fail3_total = 0
local function assert3(label, got_s, got_e, exp_s, exp_e)
	local ok = (got_s == exp_s and got_e == exp_e)
	if ok then
		pass3_total = pass3_total + 1
	else
		fail3_total = fail3_total + 1
		print(string.format("FAIL: %s 实际值 %d-%d, 期望值 %d-%d", label, got_s or 0, got_e or 0, exp_s, exp_e))
	end
	return ok
end

-- 3.1 交叉嵌套验证
assert3("3.1 {}[0]正向",  cx_s1, cx_e1, 1, 9)
assert3("3.1 {}[1]正向",  cx_s2, cx_e2, 2, 4)
assert3("3.1 {}[2]正向",  cx_s3, cx_e3, 5, 8)
assert3("3.1 {}[-1]倒序", cx_r1, cx_f1, 5, 8)
assert3("3.1 {}[-2]倒序", cx_r2, cx_f2, 2, 4)
assert3("3.1 {}[-3]倒序", cx_r3, cx_f3, 1, 9)
assert3("3.1 ()[0]正向",  cx_p1, cx_q1, 2, 2)
assert3("3.1 ()[1]正向",  cx_p2, cx_q2, 3, 3)
assert3("3.1 ()[2]正向",  cx_p3, cx_q3, 5, 5)
assert3("3.1 ()[3]正向",  cx_p4, cx_q4, 7, 7)
assert3("3.1 ()[-1]倒序", cx_rp1, cx_fp1, 7, 7)
assert3("3.1 ()[-2]倒序", cx_rp2, cx_fp2, 5, 5)
assert3("3.1 [][0]正向",  cx_sb1, cx_eb1, 3, 3)
assert3("3.1 [][1]正向",  cx_sb2, cx_eb2, 6, 6)
assert3("3.1 [][-1]倒序", cx_rs1, cx_fe1, 6, 6)
assert3("3.1 [][-2]倒序", cx_rs2, cx_fe2, 3, 3)

-- 3.2 深度嵌套验证
assert3("3.2 {}[0]正向",  dp_s1, dp_e1, 1, 19)
assert3("3.2 {}[1]正向",  dp_s2, dp_e2, 2, 18)
assert3("3.2 {}[2]正向",  dp_s3, dp_e3, 3, 17)
assert3("3.2 {}[3]正向",  dp_s4, dp_e4, 5, 15)
assert3("3.2 {}[4]正向",  dp_s5, dp_e5, 6, 6)
assert3("3.2 {}[5]正向",  dp_s6, dp_e6, 7, 9)
assert3("3.2 {}[6]正向",  dp_s7, dp_e7, 10, 10)
assert3("3.2 {}[7]正向",  dp_s8, dp_e8, 11, 13)
assert3("3.2 {}[-1]倒序", dp_r1, dp_f1, 11, 13)
assert3("3.2 {}[-2]倒序", dp_r2, dp_f2, 10, 10)
assert3("3.2 {}[-3]倒序", dp_r3, dp_f3, 7, 9)
assert3("3.2 {}[-4]倒序", dp_r4, dp_f4, 6, 6)
assert3("3.2 {}[-5]倒序", dp_r5, dp_f5, 5, 15)
assert3("3.2 {}[-6]倒序", dp_r6, dp_f6, 3, 17)
assert3("3.2 {}[-7]倒序", dp_r7, dp_f7, 2, 18)
assert3("3.2 {}[-8]倒序", dp_r8, dp_f8, 1, 19)
assert3("3.2 ()[0]正向",  dp_p1, dp_q1, 3, 3)
assert3("3.2 ()[1]正向",  dp_p2, dp_q2, 4, 4)
assert3("3.2 ()[2]正向",  dp_p3, dp_q3, 7, 7)
assert3("3.2 ()[3]正向",  dp_p4, dp_q4, 11, 11)
assert3("3.2 ()[4]正向",  dp_p5, dp_q5, 12, 12)
assert3("3.2 ()[5]正向",  dp_p6, dp_q6, 14, 14)
assert3("3.2 ()[-1]倒序", dp_rp1, dp_fp1, 14, 14)
assert3("3.2 ()[-2]倒序", dp_rp2, dp_fp2, 12, 12)
assert3("3.2 ()[-3]倒序", dp_rp3, dp_fp3, 11, 11)

-- 3.3 连续闭合验证
assert3("3.3 {}[0]正向",  cc_s1, cc_e1, 1, 10)
assert3("3.3 {}[1]正向",  cc_s2, cc_e2, 2, 10)
assert3("3.3 {}[2]正向",  cc_s3, cc_e3, 3, 3)
assert3("3.3 {}[3]正向",  cc_s4, cc_e4, 6, 8)
assert3("3.3 {}[-1]倒序", cc_r1, cc_f1, 6, 8)
assert3("3.3 {}[-2]倒序", cc_r2, cc_f2, 3, 3)
assert3("3.3 {}[-3]倒序", cc_r3, cc_f3, 2, 10)
assert3("3.3 {}[-4]倒序", cc_r4, cc_f4, 1, 10)
assert3("3.3 ()[0]正向",  cc_p1, cc_q1, 2, 2)
assert3("3.3 ()[1]正向",  cc_p2, cc_q2, 4, 4)
assert3("3.3 ()[2]正向",  cc_p3, cc_q3, 5, 5)
assert3("3.3 ()[3]正向",  cc_p4, cc_q4, 6, 6)
assert3("3.3 ()[4]正向",  cc_p5, cc_q5, 7, 7)
assert3("3.3 ()[-1]倒序", cc_rp1, cc_fp1, 7, 7)
assert3("3.3 ()[-2]倒序", cc_rp2, cc_fp2, 6, 6)
assert3("3.3 ()[-3]倒序", cc_rp3, cc_fp3, 5, 5)

print(string.format("\n总计: %d 通过, %d 失败, 共 %d 项断言",
	pass3_total, fail3_total, pass3_total + fail3_total))

if fail3_total == 0 then
	print("PASS: 所有跨行嵌套索引语义测试通过")
else
	print(string.format("FAIL: %d 项测试未通过", fail3_total))
end

return M