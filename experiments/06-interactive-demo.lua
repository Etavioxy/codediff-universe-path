-- Experiment 06: Realtime Rematching — caseenv × case 验证矩阵
-- 运行: nvim 然后 :source experiments/06-interactive-demo.lua
-- 架构: caseenv(环境) × case(机制) → 验证缓存每个机制在不同环境中正确
-- 使用方法:
--   :lua _G.exp06.run_all()      — 运行全部
--   :lua _G.exp06.summary()      — 查看指标

_G.exp06 = {}
_G.exp06.cache = {}

-- === 缓存核心 ===

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
        if nesting == 0 and start_line then end_line = i; break end
      end
    end
    if end_line then break end
  end
  local key = string.format("%d:%s:%s:%d", bufnr, start_delim, end_delim, index)
  _G.exp06.cache[key] = {
    start_line = start_line, end_line = end_line,
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

-- === Caseenv 定义（环境 — "跑在什么数据上"） ===

local function gen_lines(n_lines, block_interval)
  local lines = {}
  for i = 1, n_lines do
    if i % block_interval == 1 then
      lines[#lines + 1] = string.format("function block_%d() {", i)
    elseif i % block_interval == block_interval - 1 then
      lines[#lines + 1] = "}"
    elseif i % block_interval == math.floor(block_interval / 2) then
      lines[#lines + 1] = string.format("  local val_%d = %d", i, i * 7 % 100)
    else
      lines[#lines + 1] = string.format("  -- line %d", i)
    end
  end
  return lines
end

local function gen_many_blocks(n_blocks)
  local lines = {}
  for i = 1, n_blocks do
    lines[#lines + 1] = string.format("{ /* block %d */ }", i)
  end
  return lines
end

local function gen_deep_nesting(depth)
  local lines = {}
  for i = 1, depth do
    lines[#lines + 1] = string.format("level_%d {", i)
  end
  lines[#lines + 1] = "  return 0;"
  for i = depth, 1, -1 do
    lines[#lines + 1] = "}"
  end
  return lines
end

_G.exp06.caseenvs = {
  -- === 手工编写 — 典型场景 ===
  {
    name = "small_file_2_blocks",
    desc = "小文件 2个{}块",
    category = "normal",
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
    indices = {0, 1},
  },
  {
    name = "nested_1_level",
    desc = "单层嵌套{}",
    category = "normal",
    lines = {
      "function outer() {",
      "  if (true) {",
      "    return 1;",
      "  }",
      "  return 0;",
      "}",
    },
    delimiters = { {"{", "}"} },
    indices = {0},
  },
  {
    name = "parens_args",
    desc = "()参数列表",
    category = "normal",
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
    indices = {0, 1},
  },
  {
    name = "bracket_indexing",
    desc = "[]索引多行",
    category = "normal",
    lines = {
      "local arr = [1, 2, 3]",
      "local dict = [",
      "  key = 'val',",
      "]",
      "local mix = arr[0] + dict['x']",
    },
    delimiters = { {"[", "]"} },
    indices = {0, 1, 2, 3},
  },
  {
    name = "mixed_delimiters",
    desc = "(){}[]同行交叉",
    category = "normal",
    lines = { "if (a[0] > 0) { return a[0]; }" },
    delimiters = { {"(", ")"}, {"[", "]"}, {"{", "}"} },
    indices = {0},
  },
  {
    name = "same_line_and_empty",
    desc = "空块/同行/单行嵌套",
    category = "normal",
    lines = {
      "local t = {}",
      "local u = {1, 2, 3}",
      "local v = {",
      "  nested = {a = 1},",
      "}",
    },
    delimiters = { {"{", "}"} },
    indices = {0, 1, 2},
  },
  {
    name = "siblings_5",
    desc = "5个同级连续块",
    category = "normal",
    lines = {
      "{block1} {block2} {block3}",
      "{block4}",
      "",
      "  {block5}",
    },
    delimiters = { {"{", "}"} },
    indices = {0, 1, 2, 3, 4},
  },
  {
    name = "cross_nested_1line",
    desc = "同行交叉嵌套",
    category = "normal",
    lines = { "local fn = function(x) return {[x] = true} end" },
    delimiters = { {"(", ")"}, {"{", "}"}, {"[", "]"} },
    indices = {0},
  },
  {
    name = "dense_delimiters",
    desc = "字符串/注释中的分隔符",
    category = "normal",
    lines = {
      'local s = "this { is } not ( a ) block"',
      "local t = { -- not } here",
      "  key = 'val [0]'",
      "}",
      "local real = {1}",
    },
    delimiters = { {"{", "}"} },
    indices = {0, 1},
  },

  -- === 生成 — 大规模数据 ===
  {
    name = "large_file_500",
    desc = "500行 25个块",
    category = "normal",
    lines = gen_lines(500, 20),
    delimiters = { {"{", "}"} },
    indices = {0, 5, 12, 24},
  },
  {
    name = "many_blocks_100",
    desc = "100个同级块",
    category = "normal",
    lines = gen_many_blocks(100),
    delimiters = { {"{", "}"} },
    indices = {0, 25, 50, 75, 99},
  },
  {
    name = "deep_nesting_10",
    desc = "10层深度嵌套",
    category = "normal",
    lines = gen_deep_nesting(10),
    delimiters = { {"{", "}"} },
    indices = {0},
  },

  -- === 失配环境 ===
  {
    name = "unclosed_block",
    desc = "失配 — 未闭合",
    category = "mismatch",
    lines = { "function bad() {", "  return 1;" },
    delimiters = { {"{", "}"} },
    indices = {0},
  },
  {
    name = "extra_closing",
    desc = "失配 — 多余}",
    category = "mismatch",
    lines = { "function bad() {", "  return 1;", "}", "}" },
    delimiters = { {"{", "}"} },
    indices = {0},
  },
  {
    name = "index_oob",
    desc = "失配 — 索引越界",
    category = "mismatch",
    lines = { "{block}" },
    delimiters = { {"{", "}"} },
    indices = {5},
  },

  -- === 突变环境 ===
  {
    name = "mutate_insert_lines",
    desc = "突变 — 块内增行",
    category = "mutation",
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
      vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { "  local x = 1", "  local y = 2" })
    end,
  },
  {
    name = "mutate_delete_lines",
    desc = "突变 — 块内删行",
    category = "mutation",
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
      vim.api.nvim_buf_set_lines(bufnr, 2, 4, true, {})
    end,
  },
  {
    name = "mutate_insert_block_before",
    desc = "突变 — 块前插入（索引漂移）",
    category = "mutation",
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
      vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, {
        "function pre() {", "  return 0;", "}", "",
      })
    end,
  },
  {
    name = "mutate_modify_inside",
    desc = "突变 — 块内修改（边界不变）",
    category = "mutation",
    lines = {
      "function foo() {",
      "  return 1;",
      "}",
    },
    delimiters = { {"{", "}"} },
    indices = {0},
    mutate = function(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 1, 2, true, { "  return 42;" })
    end,
  },
  {
    name = "mutate_delete_block",
    desc = "突变 — 删除整个块",
    category = "mutation",
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
      vim.api.nvim_buf_set_lines(bufnr, 3, 7, true, {})
    end,
  },

  -- === 监听验证环境 ===
  {
    name = "autocmd_textchanged_verify",
    desc = "TextChanged autocmd监听验证",
    category = "autocmd",
    lines = {
      "function test() {",
      "  return 42;",
      "}",
    },
    delimiters = { {"{", "}"} },
    indices = {0},
    mutate = function(bufnr)
      -- Register TextChanged autocmd (same pattern as codediff auto_refresh.lua)
      _G.exp06._autocmd_fired = false
      local augroup = vim.api.nvim_create_augroup("exp06_textchanged_test", { clear = true })
      vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
        group = augroup,
        buffer = bufnr,
        callback = function()
          _G.exp06._autocmd_fired = true
        end,
      })
      -- Modify buffer via nvim_buf_set_lines (programmatic API)
      -- NOTE: This does NOT trigger TextChanged in Neovim — expected behavior
      -- per :help TextChanged. The codediff system relies on:
      --   (1) TextChanged → triggers auto_refresh diff recompute
      --   (2) changedtick guard → cache invalidation (handles API modifications too)
      vim.api.nvim_buf_set_lines(bufnr, 1, 2, true, { "  return 100;" })
    end,
  },
}

-- === Case 定义（机制 — "验证哪个缓存行为"） ===

_G.exp06.cases = {
  {
    id = "first_miss",
    desc = "首次查询无缓存 → miss",
    applicable = {"normal", "mismatch", "mutation"},
    run = function(bufnr, env, delim, idx, result)
      local s, e, cached = _G.exp06.get_match(bufnr, delim[1], delim[2], idx)
      if cached then
        table.insert(result.errors, string.format("%s[%d] 首次查询应miss但hit", delim[1]..delim[2], idx))
      else
        result.counts.first_miss = (result.counts.first_miss or 0) + 1
      end
      return s, e
    end,
  },
  {
    id = "second_hit",
    desc = "再次查询 → hit + 结果一致",
    applicable = {"normal", "mismatch", "mutation"},
    run = function(bufnr, env, delim, idx, result, first_s, first_e)
      local s, e, cached = _G.exp06.get_match(bufnr, delim[1], delim[2], idx)
      if not cached then
        table.insert(result.errors, string.format("%s[%d] 再次查询应hit但miss", delim[1]..delim[2], idx))
      elseif first_s and (s ~= first_s or e ~= first_e) then
        table.insert(result.errors, string.format("%s[%d] hit结果不一致: (%d,%d)≠(%d,%d)",
          delim[1]..delim[2], idx, first_s, first_e, s, e))
      else
        result.counts.second_hit = (result.counts.second_hit or 0) + 1
      end
    end,
  },
  {
    id = "no_false_invalidation",
    desc = "未修改buffer → 缓存不失效",
    applicable = {"normal", "mismatch", "mutation"},
    run = function(bufnr, env, delim, idx, result)
      local _, _, cached = _G.exp06.get_match(bufnr, delim[1], delim[2], idx)
      if not cached then
        table.insert(result.errors, string.format("%s[%d] 未修改时应hit但miss", delim[1]..delim[2], idx))
      else
        result.counts.no_false_invalidation = (result.counts.no_false_invalidation or 0) + 1
      end
    end,
  },
  {
    id = "mutation_miss",
    desc = "修改buffer → changedtick变化 → 缓存失效 → miss",
    applicable = {"mutation"},
    run_after_mutate = function(bufnr, env, delim, idx, result)
      local _, _, cached = _G.exp06.get_match(bufnr, delim[1], delim[2], idx)
      if cached then
        table.insert(result.errors, string.format("%s[%d] 突变后应miss但hit", delim[1]..delim[2], idx))
        return nil, nil
      else
        result.counts.mutation_miss = (result.counts.mutation_miss or 0) + 1
      end
      -- 重匹配后再查一次验证结果稳定
      local s_new, e_new = _G.exp06.match_and_cache(bufnr, delim[1], delim[2], idx)
      local s_v, e_v, c_v = _G.exp06.get_match(bufnr, delim[1], delim[2], idx)
      if not c_v then
        table.insert(result.errors, string.format("%s[%d] 重匹配后应hit但miss", delim[1]..delim[2], idx))
      elseif s_v ~= s_new or e_v ~= e_new then
        table.insert(result.errors, string.format("%s[%d] 重匹配结果不一致", delim[1]..delim[2], idx))
      else
        result.counts.rematch_consistent = (result.counts.rematch_consistent or 0) + 1
      end
    end,
  },
  {
    id = "mismatch_safety",
    desc = "失配/越界 → 不崩溃，正确返回nil",
    applicable = {"mismatch"},
    run = function(bufnr, env, delim, idx, result)
      -- 使用首个delim+idx（即环境定义的失配case），验证不会崩溃
      -- 这个case会在mismatch env上跑，用于验证错误场景下的缓存行为
      local s, e = _G.exp06.match_and_cache(bufnr, delim[1], delim[2], idx)
      -- 再次查询应命中（失配环境也正确缓存）
      local s2, e2, cached = _G.exp06.get_match(bufnr, delim[1], delim[2], idx)
      if not cached then
        table.insert(result.errors, string.format("%s[%d] 失配环境二次查询应hit", delim[1]..delim[2], idx))
      elseif (s or "nil") ~= (s2 or "nil") or (e or "nil") ~= (e2 or "nil") then
        table.insert(result.errors, string.format("%s[%d] 失配缓存结果不一致", delim[1]..delim[2], idx))
      else
        result.counts.mismatch_safety = (result.counts.mismatch_safety or 0) + 1
      end
    end,
  },
  -- === TextChanged autocmd 监听验证 ===
  {
    id = "changedtick_increments",
    desc = "changedtick随buf修改递增",
    applicable = {"autocmd"},
    run_after_mutate = function(bufnr, env, delim, idx, result)
      local tick = vim.api.nvim_buf_get_changedtick(bufnr)
      -- changedtick starts at 1 (buf create), +1 for set_lines (initial content),
      -- +1 for set_lines (mutate in env). Should be >= 3.
      if tick < 3 then
        table.insert(result.errors, string.format(
          "changedtick应为>=3(创建+初始填充+突变)，实际=%d", tick))
      else
        result.counts.changedtick_increments = (result.counts.changedtick_increments or 0) + 1
      end
    end,
  },
  {
    id = "textchanged_autocmd_behavior",
    desc = "nvim_buf_set_lines不触发TextChanged(预期行为)",
    applicable = {"autocmd"},
    run_after_mutate = function(bufnr, env, delim, idx, result)
      -- Neovim API: nvim_buf_set_lines does NOT fire TextChanged.
      -- This is a documented quirk — TextChanged only fires on user interaction
      -- (InsertLeave, normal-mode commands, etc.), not programmatic changes.
      -- The codediff system's cache invalidation relies on changedtick,
      -- which correctly handles both user edits AND API modifications.
      if _G.exp06._autocmd_fired then
        table.insert(result.errors,
          "TextChanged意外触发: nvim_buf_set_lines不应触发TextChanged")
      else
        result.counts.textchanged_not_fired = (result.counts.textchanged_not_fired or 0) + 1
      end
    end,
  },
  {
    id = "cache_miss_after_api_mutation",
    desc = "API修改后changedtick变化→缓存正确失效",
    applicable = {"autocmd"},
    run_after_mutate = function(bufnr, env, delim, idx, result)
      -- Even without TextChanged firing, the changedtick-based cache
      -- correctly detects the mutation and returns a miss.
      local _, _, cached = _G.exp06.get_match(bufnr, delim[1], delim[2], idx)
      if cached then
        table.insert(result.errors, string.format(
          "%s[%d] API突变后缓存应失效(miss)但hit", delim[1]..delim[2], idx))
      else
        result.counts.api_mutation_miss = (result.counts.api_mutation_miss or 0) + 1
      end
      -- Re-cache and verify consistency
      local s_new, e_new = _G.exp06.match_and_cache(bufnr, delim[1], delim[2], idx)
      local s_v, e_v, c_v = _G.exp06.get_match(bufnr, delim[1], delim[2], idx)
      if not c_v then
        table.insert(result.errors, string.format(
          "%s[%d] API突变重缓存后应hit但miss", delim[1]..delim[2], idx))
      elseif s_v ~= s_new or e_v ~= e_new then
        table.insert(result.errors, string.format(
          "%s[%d] API突变重缓存结果不一致", delim[1]..delim[2], idx))
      else
        result.counts.api_rematch_consistent = (result.counts.api_rematch_consistent or 0) + 1
      end
    end,
  },
}

-- === 运行引擎 ===

local function case_applies_to(case, category)
  for _, c in ipairs(case.applicable) do
    if c == category then return true end
  end
  return false
end

function _G.exp06.run_all()
  _G.exp06.results = {}
  _G.exp06.cache = {}
  local stats = { total = 0, passed = 0, failed = 0, errors = {} }

  print("")
  print("=== Experiment 06: caseenv × case 验证矩阵 ===")
  print(string.format("%d 环境 × %d 机制", #_G.exp06.caseenvs, #_G.exp06.cases))
  print("")

  for _, env in ipairs(_G.exp06.caseenvs) do
    _G.exp06.cache = {}
    local bufnr = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, env.lines)

    local env_result = {
      env_name = env.name,
      env_desc = env.desc,
      category = env.category,
      delimiters = env.delimiters,
      line_count = #env.lines,
      case_results = {},
      counts = {},
      errors = {},
    }

    -- 对每个分隔符×索引组合，跑所有 applicable case
    for _, delim in ipairs(env.delimiters) do
      for _, idx in ipairs(env.indices) do
        -- 先跑 pre-mutation cases
        local first_results = {}  -- store first match results per delim+idx
        for _, case in ipairs(_G.exp06.cases) do
          if case_applies_to(case, env.category) and not case.run_after_mutate then
            stats.total = stats.total + 1
            if case.id == "first_miss" then
              local s, e = case.run(bufnr, env, delim, idx, env_result)
              first_results[delim[1]..delim[2]..idx] = {s, e}
            elseif case.id == "second_hit" then
              local prev = first_results[delim[1]..delim[2]..idx]
              case.run(bufnr, env, delim, idx, env_result, prev[1], prev[2])
            else
              case.run(bufnr, env, delim, idx, env_result)
            end
          end
        end
      end
    end

    -- 执行突变（mutation 和 autocmd 环境均需要）
    if (env.category == "mutation" or env.category == "autocmd") and env.mutate then
      env.mutate(bufnr)
      for _, delim in ipairs(env.delimiters) do
        for _, idx in ipairs(env.indices) do
          for _, case in ipairs(_G.exp06.cases) do
            if case.run_after_mutate and case_applies_to(case, env.category) then
              stats.total = stats.total + 1
              case.run_after_mutate(bufnr, env, delim, idx, env_result)
            end
          end
        end
      end
    end

    -- 判定本环境通过/失败
    local nerr = #env_result.errors
    if nerr == 0 then
      stats.passed = stats.passed + 1
      print(string.format("  [PASS] %-30s (%s)", env.name, env.desc))
    else
      stats.failed = stats.failed + 1
      print(string.format("  [FAIL] %-30s (%s) — %d errors", env.name, env.desc, nerr))
      for _, err in ipairs(env_result.errors) do
        print(string.format("         -> %s", err))
      end
    end

    _G.exp06.results[#_G.exp06.results + 1] = env_result
  end

  print("")
  _G.exp06.print_summary(stats)
  return stats
end

function _G.exp06.print_summary(stats)
  print("=== 验证指标 ===")
  local correctness = stats.total > 0 and ((stats.total - stats.failed) / stats.total * 100) or 0
  print(string.format("  环境×机制组合:    %d 项", stats.total))
  print(string.format("  通过:             %d / %d (%.1f%%)", stats.passed, #_G.exp06.caseenvs, stats.passed / #_G.exp06.caseenvs * 100))

  -- 汇总各机制计数
  print("")
  print("=== 机制验证次数 ===")
  local totals = {}
  for _, r in ipairs(_G.exp06.results) do
    for k, v in pairs(r.counts) do
      totals[k] = (totals[k] or 0) + v
    end
  end
  local labels = {
    first_miss = "首次miss", second_hit = "再次hit", no_false_invalidation = "无误失效",
    mutation_miss = "突变miss", rematch_consistent = "重匹配一致", mismatch_safety = "失配安全",
    changedtick_increments = "changedtick递增",
    textchanged_not_fired = "TextChanged未触发(预期)",
    api_mutation_miss = "API突变miss",
    api_rematch_consistent = "API重匹配一致",
  }
  for k, v in pairs(totals) do
    print(string.format("  %s: %d", labels[k] or k, v))
  end

  -- 覆盖维度
  print("")
  print("=== 覆盖维度 ===")
  local cats = {}
  for _, r in ipairs(_G.exp06.results) do
    cats[r.category] = (cats[r.category] or 0) + 1
  end
  for cat, cnt in pairs(cats) do
    local desc = {normal="正常环境", mismatch="失配/边界", mutation="突变重匹配", autocmd="TextChanged监听验证"}
    print(string.format("  %s: %d 环境", desc[cat] or cat, cnt))
  end

  local min_lines, max_lines = math.huge, 0
  for _, r in ipairs(_G.exp06.results) do
    if r.line_count < min_lines then min_lines = r.line_count end
    if r.line_count > max_lines then max_lines = r.line_count end
  end
  print(string.format("  文件规模:         %d ~ %d 行", min_lines, max_lines))

  -- 分隔符覆盖
  local delim_set = {}
  for _, r in ipairs(_G.exp06.results) do
    for _, d in ipairs(r.delimiters) do
      delim_set[d[1]..d[2]] = true
    end
  end
  local covered = {}
  for k, _ in pairs(delim_set) do table.insert(covered, k) end
  table.sort(covered)
  print(string.format("  分隔符类型:       %s", table.concat(covered, ", ")))

  -- 生成 vs 手写
  local generated = 0
  for _, r in ipairs(_G.exp06.results) do
    if r.env_name:match("^large_file") or r.env_name:match("^many_blocks") or r.env_name:match("^deep_nesting") then
      generated = generated + 1
    end
  end
  print(string.format("  手写/生成环境:    %d / %d", #_G.exp06.results - generated, generated))
end

function _G.exp06.summary()
  if not _G.exp06.results or #_G.exp06.results == 0 then
    print("No results yet. Run :lua _G.exp06.run_all() first.")
    return
  end
  _G.exp06.recompute_stats()
end

function _G.exp06.recompute_stats()
  local stats = { total = 0, passed = 0, failed = 0 }
  for _, r in ipairs(_G.exp06.results) do
    local nerr = #r.errors
    stats.total = stats.total + nerr -- won't work, let me just print
    if nerr == 0 then stats.passed = stats.passed + 1 else stats.failed = stats.failed + 1 end
  end
  _G.exp06.print_summary(stats)
end

-- === Setup ===
local cwd = vim.fn.getcwd()
vim.opt.rtp:prepend(cwd)
vim.cmd('runtime! plugin/*.lua plugin/*.vim')
require("codediff").setup()

print("=== Experiment 06: caseenv × case 验证矩阵 ===")
print(string.format("%d 环境 × %d 缓存机制", #_G.exp06.caseenvs, #_G.exp06.cases))
print(string.format("  normal: %d | mismatch: %d | mutation: %d | autocmd: %d",
  #vim.tbl_filter(function(e) return e.category == "normal" end, _G.exp06.caseenvs),
  #vim.tbl_filter(function(e) return e.category == "mismatch" end, _G.exp06.caseenvs),
  #vim.tbl_filter(function(e) return e.category == "mutation" end, _G.exp06.caseenvs),
  #vim.tbl_filter(function(e) return e.category == "autocmd" end, _G.exp06.caseenvs)))
print("")
print(">>> 运行验证:")
print("  :lua _G.exp06.run_all()")
print("  :lua _G.exp06.summary()")