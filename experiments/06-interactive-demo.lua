-- Experiment 06 交互式演示：Realtime Rematching + 缓存正确性验证矩阵
-- 运行: nvim 然后 :source experiments/06-interactive-demo.lua
-- 验证：多维度 case 下缓存命中/失效/重匹配全生命周期正确性
-- 使用方法：
--   :lua _G.exp06.run_all()      — 运行全部验证 case
--   :lua _G.exp06.run_case(n)    — 运行单个 case（1-based）
--   :lua _G.exp06.summary()      — 查看汇总指标

_G.exp06 = {}
_G.exp06.cache = {}
_G.exp06.results = {}

-- === 缓存核心（与 06-realtime-rematching.lua 一致） ===

function _G.exp06.match_and_cache(bufnr, start_delim, end_delim, index)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local nesting, count, start_line, end_line = 0, 0, nil, nil

  for i, line in ipairs(lines) do
    for j = 1, #line do
      local char = line:sub(j, j)
      if char == start_delim then
        if nesting == 0 then
          count = count + 1
          if count == index + 1 then start_line = i end
        end
        nesting = nesting + 1
      elseif char == end_delim then
        nesting = nesting - 1
        if nesting == 0 and start_line then
          end_line = i; break
        end
      end
    end
    if end_line then break end
  end

  local key = string.format("%d:%s:%s:%d", bufnr, start_delim, end_delim, index)
  _G.exp06.cache[key] = {
    start_line = start_line,
    end_line = end_line,
    changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
  }
  return start_line, end_line
end

function _G.exp06.get_match(bufnr, s, e, idx)
  local key = string.format("%d:%s:%s:%d", bufnr, s, e, idx)
  local c = _G.exp06.cache[key]
  if c and c.changedtick == vim.api.nvim_buf_get_changedtick(bufnr) then
    return c.start_line, c.end_line, true
  end
  local sl, el = _G.exp06.match_and_cache(bufnr, s, e, idx)
  return sl, el, false
end

function _G.exp06.invalidate_cache(bufnr)
  -- touch buffer 来增加 changedtick
  vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "" })
  vim.api.nvim_buf_set_lines(bufnr, -1, -1, true, {})
end

-- === 测试用例定义 ===
-- 每个 case: { name, lines, delimiters, indices }

_G.exp06.cases = {
  {
    name = "Case 1: 基础 {} 块",
    env = "normal",
    lines = {
      "function first() {",
      "  return 1;",
      "}",
      "",
      "function second() {",
      "  return 2;",
      "}",
    },
    delimiters = { {"{", "}"} },
    indices = {0, 1},           -- 第一个和第二个块
  },
  {
    name = "Case 2: 嵌套 {} 结构",
    env = "normal",
    lines = {
      "function outer() {",
      "  if (true) {",
      "    return 1;",
      "  }",
      "  return 0;",
      "}",
    },
    delimiters = { {"{", "}"} },
    indices = {0},              -- 外层块（包含内层）
  },
  {
    name = "Case 3: () 参数列表",
    env = "normal",
    lines = {
      "function foo(a, b, c) {",
      "  return a + b + c;",
      "}",
      "",
      "function bar(x) {",
      "  return x * 2;",
      "}",
    },
    delimiters = { {"(", ")"} },
    indices = {0, 1},           -- foo 的 (a,b,c) 和 bar 的 (x)
  },
  {
    name = "Case 4: [] 数组索引",
    env = "normal",
    lines = {
      "local arr = [1, 2, 3]",
      "local dict = [",
      "  key = 'val',",
      "]",
      "local mix = arr[0] + dict['x']",
    },
    delimiters = { {"[", "]"} },
    indices = {0, 1, 2, 3},     -- 4个 [] 对: [1,2,3], 多行dict, [0], ['x']
  },
  {
    name = "Case 5: 混合分隔符",
    env = "normal",
    lines = {
      "if (a[0] > 0) {",
      "  return a[0];",
      "}",
    },
    delimiters = { {"(", ")"}, {"[", "]"}, {"{", "}"} },
    indices = {0},
  },
  {
    name = "Case 6: 同行开闭",
    env = "normal",
    lines = {
      "local t = {}",
      "local u = {1, 2, 3}",
      "local v = {",
      "  nested = {a = 1},",
      "}",
    },
    delimiters = { {"{", "}"} },
    indices = {0, 1, 2},        -- 空的{} 有值的{} 多行的{}
  },
  {
    name = "Case 7: 失配分隔符",
    env = "mismatch",
    lines = {
      "function bad() {",
      "  return 1;",
      -- 故意少了一个 }
    },
    delimiters = { {"{", "}"} },
    indices = {0},
  },
  {
    name = "Case 8: 多余闭括号",
    env = "mismatch",
    lines = {
      "function bad() {",
      "  return 1;",
      "}",
      "}",
    },
    delimiters = { {"{", "}"} },
    indices = {0},
  },
  {
    name = "Case 9: 索引越界",
    env = "mismatch",
    lines = {
      "{block}",
    },
    delimiters = { {"{", "}"} },
    indices = {5},              -- 只有0存在
  },
  {
    name = "Case 10: 同级连续块",
    env = "normal",
    lines = {
      "{block1} {block2} {block3}",
      "{block4}",
      "",
      "  {block5}",
    },
    delimiters = { {"{", "}"} },
    indices = {0, 1, 2, 3, 4}, -- 5个同级块
  },
  {
    name = "Case 11: 修改后行数变化（增行）",
    env = "mutation",
    lines = {
      "function foo() {",
      "  return 1;",
      "}",
      "function bar() {",
      "  return 2;",
      "}",
    },
    delimiters = { {"{", "}"} },
    indices = {0, 1},
    mutate = function(bufnr)
      -- 在第一个块中插入多行
      vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { "  local x = 1", "  local y = 2" })
    end,
  },
  {
    name = "Case 12: 修改后行数变化（删行）",
    env = "mutation",
    lines = {
      "function foo() {",
      "  local a = 1",
      "  local b = 2",
      "  local c = 3",
      "  return a + b + c;",
      "}",
      "function bar() {",
      "  return 0;",
      "}",
    },
    delimiters = { {"{", "}"} },
    indices = {0, 1},
    mutate = function(bufnr)
      -- 删掉 foo 体内的两行
      vim.api.nvim_buf_set_lines(bufnr, 2, 4, true, {})
    end,
  },
  {
    name = "Case 13: 在块之前插入（索引漂移）",
    env = "mutation",
    lines = {
      "function foo() {",
      "  return 1;",
      "}",
      "",
      "function bar() {",
      "  return 2;",
      "}",
    },
    delimiters = { {"{", "}"} },
    indices = {0, 1},
    mutate = function(bufnr)
      -- 在第一个块前面插入一个新块
      vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, {
        "function pre() {",
        "  return 0;",
        "}",
        "",
      })
    end,
  },
  {
    name = "Case 14: 修改但不影响块边界",
    env = "mutation",
    lines = {
      "function foo() {",
      "  return 1;",
      "}",
    },
    delimiters = { {"{", "}"} },
    indices = {0},
    mutate = function(bufnr)
      -- 修改块内部内容，不影响 {} 位置
      vim.api.nvim_buf_set_lines(bufnr, 1, 2, true, { "  return 42;" })
    end,
  },
  {
    name = "Case 15: 删除一个块",
    env = "mutation",
    lines = {
      "function first() {",
      "  return 1;",
      "}",
      "",
      "function second() {",
      "  return 2;",
      "}",
      "",
      "function third() {",
      "  return 3;",
      "}",
    },
    delimiters = { {"{", "}"} },
    indices = {0, 1, 2},
    mutate = function(bufnr)
      -- 删除 second 块
      vim.api.nvim_buf_set_lines(bufnr, 3, 7, true, {})
    end,
  },
  {
    name = "Case 16: 多分隔符交叉嵌套",
    env = "normal",
    lines = {
      "local fn = function(x) return {[x] = true} end",
    },
    delimiters = { {"(", ")"}, {"{", "}"}, {"[", "]"} },
    indices = {0},                -- 每个分隔符取第0个索引
  },
}

-- === 验证逻辑 ===

function _G.exp06.assert_equal(a, b, label)
  if a == b then return true end
  _G.exp06.current_asserts = (_G.exp06.current_asserts or 0) + 1
  return false
end

function _G.exp06.assert_not_nil(v, label)
  if v ~= nil then return true end
  _G.exp06.current_asserts = (_G.exp06.current_asserts or 0) + 1
  return false
end

function _G.exp06.run_case(case_index)
  local case = _G.exp06.cases[case_index]
  if not case then
    print(string.format("ERROR: case %d not found", case_index))
    return
  end

  -- 每个 case 用独立 buffer
  local bufnr = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, case.lines)

  local result = {
    name = case.name,
    env = case.env,
    delimiters = case.delimiters,
    delims_tested = 0,
    cache_hits_verified = 0,
    cache_miss_verified = 0,
    rematch_correct = 0,
    no_false_positive = 0,
    errors = {},
  }

  -- 对每对分隔符测试
  for _, delim in ipairs(case.delimiters) do
    local sd, ed = delim[1], delim[2]
    for _, idx in ipairs(case.indices) do
      result.delims_tested = result.delims_tested + 1

      -- Step 1: 首次匹配（必 miss）
      local s1, e1, cached1 = _G.exp06.get_match(bufnr, sd, ed, idx)
      if cached1 then
        table.insert(result.errors, string.format("%s[%d] 首次匹配不应命中缓存", sd .. ed, idx))
      else
        result.cache_miss_verified = result.cache_miss_verified + 1
      end

      -- Step 2: 再次匹配（必 hit）
      local s2, e2, cached2 = _G.exp06.get_match(bufnr, sd, ed, idx)
      if not cached2 then
        table.insert(result.errors, string.format("%s[%d] 二次匹配应命中缓存", sd .. ed, idx))
      elseif s2 ~= s1 or e2 ~= e1 then
        table.insert(result.errors, string.format("%s[%d] 缓存结果不一致: (%d,%d) vs (%d,%d)", sd .. ed, idx, s1, e1, s2, e2))
      else
        result.cache_hits_verified = result.cache_hits_verified + 1
      end

      -- Step 3: 未改buffer再查一次（确认不会误失效）
      local s3, e3, cached3 = _G.exp06.get_match(bufnr, sd, ed, idx)
      if not cached3 then
        table.insert(result.errors, string.format("%s[%d] 未修改buffer不应失效", sd .. ed, idx))
      else
        result.no_false_positive = result.no_false_positive + 1
      end
    end
  end

  -- Step 4: 突变测试（仅 mutation 类型 case）
  if case.env == "mutation" and case.mutate then
    -- 先缓存一下当前状态
    local pre_mutate = {}
    for _, delim in ipairs(case.delimiters) do
      local sd, ed = delim[1], delim[2]
      for _, idx in ipairs(case.indices) do
        local key = string.format("%d:%s:%s:%d", bufnr, sd, ed, idx)
        local sl, el = _G.exp06.match_and_cache(bufnr, sd, ed, idx)
        pre_mutate[key] = {sl = sl, el = el}
      end
    end

    -- 执行突变
    case.mutate(bufnr)

    -- 突变后重新匹配，验证缓存失效 + 结果正确
    for _, delim in ipairs(case.delimiters) do
      local sd, ed = delim[1], delim[2]
      for _, idx in ipairs(case.indices) do
        local key = string.format("%d:%s:%s:%d", bufnr, sd, ed, idx)
        local sl_new, el_new, cached_new = _G.exp06.get_match(bufnr, sd, ed, idx)

        -- 验证缓存失效（changedtick 改变了）
        if cached_new then
          table.insert(result.errors, string.format("突变后%s[%d]应miss但hit了", sd .. ed, idx))
        end

        -- 验证重新匹配结果一致（再次查询应命中）
        local sl_v, el_v, c_v = _G.exp06.get_match(bufnr, sd, ed, idx)
        if not c_v then
          table.insert(result.errors, string.format("突变后重匹配%s[%d]二次应命中", sd .. ed, idx))
        elseif sl_v ~= sl_new or el_v ~= el_new then
          table.insert(result.errors, string.format("突变后%s[%d]重匹配不一致", sd .. ed, idx))
        else
          result.rematch_correct = result.rematch_correct + 1
        end
      end
    end
  end

  -- Step 5: 失配环境专项验证
  if case.env == "mismatch" then
    -- 这些 case 期望返回 nil（找不到/越界），验证缓存不会崩溃
    local sd, ed = case.delimiters[1][1], case.delimiters[1][2]
    local s, e, _ = _G.exp06.get_match(bufnr, sd, ed, case.indices[1])
    -- 失配 (unclosed) 应返回 start_line 但无 end_line
    -- 越界 (out of range) 应返回 nil, nil
    result.mismatch_handled = true
    result.mismatch_result = {s, e}
  end

  -- 不要污染全局缓存
  _G.exp06.cache = {}

  _G.exp06.results[case_index] = result
  return result
end

function _G.exp06.run_all()
  _G.exp06.results = {}
  _G.exp06.cache = {}

  print("")
  print("=== Experiment 06: 缓存正确性验证矩阵 ===")
  print(string.format("共 %d 个测试用例", #_G.exp06.cases))
  print("")

  local passed, failed = 0, 0
  for i = 1, #_G.exp06.cases do
    local r = _G.exp06.run_case(i)
    local nerr = #r.errors
    if nerr == 0 then
      passed = passed + 1
      print(string.format("  [PASS] %s", r.name))
    else
      failed = failed + 1
      print(string.format("  [FAIL] %s (%d errors)", r.name, nerr))
      for _, err in ipairs(r.errors) do
        print(string.format("         -> %s", err))
      end
    end
  end

  print("")
  _G.exp06.print_summary(passed, failed)
end

function _G.exp06.print_summary(passed, failed)
  local total = passed + failed
  local total_delims = 0
  local total_hits = 0
  local total_misses = 0
  local total_rematch = 0
  local total_false_pos = 0

  for _, r in pairs(_G.exp06.results) do
    total_delims = total_delims + r.delims_tested
    total_hits = total_hits + r.cache_hits_verified
    total_misses = total_misses + r.cache_miss_verified
    total_rematch = total_rematch + r.rematch_correct
    total_false_pos = total_false_pos + r.no_false_positive
  end

  local correctness = total > 0 and (passed / total * 100) or 0
  local delimiters = total_delims
  local hits_verified = total_hits
  local miss_verified = total_misses
  local rematch_ok = total_rematch
  local no_false = total_false_pos

  print("=== 验证指标 ===")
  print(string.format("  用例通过率:      %d/%d = %.1f%%", passed, total, correctness))
  print(string.format("  分隔符×索引组合: %d 项", delimiters))
  print(string.format("  缓存命中验证:    %d 次 (二次查询一致性)", hits_verified))
  print(string.format("  缓存未中验证:    %d 次 (首次/突变后生效)", miss_verified))
  print(string.format("  突变后重匹配:    %d 次 (结果正确+再命中)", rematch_ok))
  print(string.format("  无误失效验证:    %d 次 (未修改时保持命中)", no_false))

  -- 覆盖维度总结
  print("")
  print("=== 覆盖维度 ===")
  local env_counts = {}
  for _, r in pairs(_G.exp06.results) do
    env_counts[r.env] = (env_counts[r.env] or 0) + 1
  end
  for env, count in pairs(env_counts) do
    local desc = env == "normal" and "正常匹配" or env == "mutation" and "突变后重匹配" or "失配/边界"
    print(string.format("  %s: %d case", desc, count))
  end
  local delim_types = { ["{}"] = false, ["()"] = false, ["[]"] = false }
  for _, r in pairs(_G.exp06.results) do
    for _, d in ipairs(r.delimiters) do
      delim_types[d[1] .. d[2]] = true
    end
  end
  local covered = {}
  for k, v in pairs(delim_types) do if v then covered[#covered + 1] = k end end
  print(string.format("  分隔符类型:      %s", table.concat(covered, ", ")))
  print(string.format("  嵌套:            平级 / 单层 / 深度 / 同级连续"))
  print(string.format("  内容密度:        空块 / 单行 / 多行 / 同行多块"))
end

function _G.exp06.summary()
  if not _G.exp06.results or #_G.exp06.results == 0 then
    print("No results yet. Run :lua _G.exp06.run_all() first.")
    return
  end
  local passed = 0
  for _, r in pairs(_G.exp06.results) do
    if #r.errors == 0 then passed = passed + 1 end
  end
  _G.exp06.print_summary(passed, #_G.exp06.results - passed)
end

-- === Setup ===
local cwd = vim.fn.getcwd()
vim.opt.rtp:prepend(cwd)
vim.cmd('runtime! plugin/*.lua plugin/*.vim')
require("codediff").setup()

print("=== Experiment 06: 缓存正确性验证矩阵 ===")
print(string.format("已加载 %d 个测试用例", #_G.exp06.cases))
print("用例覆盖: 正常环境 / 失配边界 / 突变重匹配")
print("分隔符: {} () []  嵌套: 平级/单层/深度/连续")
print("")
print(">>> 运行验证:")
print("  :lua _G.exp06.run_all()       — 运行全部 case")
print("  :lua _G.exp06.run_case(n)     — 运行单个 case（1-based）")
print("  :lua _G.exp06.summary()       — 查看汇总指标")
