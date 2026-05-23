-- Experiment 06 交互式演示：Realtime Rematching + 缓存指标
-- 运行: nvim 然后 :source experiments/06-interactive-demo.lua
-- 验证：缓存命中/失效 + 文件修改后重新匹配 + 命中率/耗时指标
-- 使用方法：source 脚本后，依次执行：
--   :lua _G.exp06.benchmark()  — 运行缓存基准测试

_G.exp06 = {}
_G.exp06.cache = {}
_G.exp06.metrics = { hits = 0, misses = 0, total_time_cached = 0, total_time_uncached = 0 }

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
  _G.exp06.cache[key] = { start_line = start_line, end_line = end_line,
    changedtick = vim.api.nvim_buf_get_changedtick(bufnr) }
  return start_line, end_line
end

function _G.exp06.get_match(bufnr, s, e, idx)
  local key = string.format("%d:%s:%s:%d", bufnr, s, e, idx)
  local c = _G.exp06.cache[key]
  if c and c.changedtick == vim.api.nvim_buf_get_changedtick(bufnr) then
    _G.exp06.metrics.hits = _G.exp06.metrics.hits + 1
    return c.start_line, c.end_line, true
  end
  _G.exp06.metrics.misses = _G.exp06.metrics.misses + 1
  local start_time = vim.loop.hrtime()
  local start_line, end_line = _G.exp06.match_and_cache(bufnr, s, e, idx)
  local elapsed = (vim.loop.hrtime() - start_time) / 1e6
  _G.exp06.metrics.total_time_uncached = _G.exp06.metrics.total_time_uncached + elapsed
  return start_line, end_line, false
end

function _G.exp06.get_match_cached_only(bufnr, s, e, idx)
  -- 仅走缓存路径不实际匹配，用于对比
  local key = string.format("%d:%s:%s:%d", bufnr, s, e, idx)
  local c = _G.exp06.cache[key]
  if c and c.changedtick == vim.api.nvim_buf_get_changedtick(bufnr) then
    return c.start_line, c.end_line, true
  end
  return nil, nil, false
end

function _G.exp06.reset_metrics()
  _G.exp06.metrics = { hits = 0, misses = 0, total_time_cached = 0, total_time_uncached = 0 }
end

function _G.exp06.benchmark()
  local bufnr = _G.exp06.bufnr
  if not bufnr then
    print("ERROR: 未找到buffer，请先 source 本脚本")
    return
  end

  local iterations = 1000
  print("")
  print(string.format(">>> 缓存基准测试 (iterations=%d) <<<", iterations))
  print("")

  -- 预热：确保缓存已填充
  _G.exp06.get_match(bufnr, "{", "}", 0)
  _G.exp06.get_match(bufnr, "{", "}", 1)

  -- 1. 纯缓存查询 (命中)
  _G.exp06.reset_metrics()
  local t0 = vim.loop.hrtime()
  for _ = 1, iterations do
    _G.exp06.get_match_cached_only(bufnr, "{", "}", 0)
    _G.exp06.get_match_cached_only(bufnr, "{", "}", 1)
  end
  local t_cached = (vim.loop.hrtime() - t0) / 1e6
  print(string.format("纯缓存查询 %d轮: %.3f ms (%.3f us/query)",
    iterations, t_cached, t_cached / (iterations * 2) * 1000))

  -- 2. 全匹配 (无缓存，通过失效后重匹配模拟)
  _G.exp06.reset_metrics()
  local t1 = vim.loop.hrtime()
  for _ = 1, iterations do
    -- 故意不改buffer所以缓存一直命中，这里直接用match_and_cache绕过缓存
    _G.exp06.match_and_cache(bufnr, "{", "}", 0)
    _G.exp06.match_and_cache(bufnr, "{", "}", 1)
  end
  local t_uncached = (vim.loop.hrtime() - t1) / 1e6
  print(string.format("全匹配 %d轮:       %.3f ms (%.3f us/query)",
    iterations, t_uncached, t_uncached / (iterations * 2) * 1000))

  local speedup = t_uncached / math.max(t_cached, 0.001)
  print(string.format("缓存加速比:        %.1fx", speedup))

  -- 3. 实际缓存命中率 (cold→hot)
  _G.exp06.reset_metrics()
  -- 追加空行再删除，使changedtick改变（缓存失效）但不改变内容
  vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "" })
  vim.api.nvim_buf_set_lines(bufnr, -1, -1, true, {})

  for _ = 1, 100 do
    _G.exp06.get_match(bufnr, "{", "}", 0)
    _G.exp06.get_match(bufnr, "{", "}", 1)
  end
  local total = _G.exp06.metrics.hits + _G.exp06.metrics.misses
  local hit_rate = total > 0 and (_G.exp06.metrics.hits / total * 100) or 0
  print(string.format("缓存命中率:        %d/%d = %.1f%% (cold->hot)",
    _G.exp06.metrics.hits, total, hit_rate))

  -- 4. 变更后失效统计
  _G.exp06.reset_metrics()
  local changes = 5
  for i = 1, changes do
    -- 修改buffer触发失效（追加一行再删除，改变changedtick）
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "// change " .. i })
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, true, {})
    -- 查询后缓存应重建
    _G.exp06.get_match(bufnr, "{", "}", 0)
    _G.exp06.get_match(bufnr, "{", "}", 1)
    -- 再次查询应命中
    _G.exp06.get_match(bufnr, "{", "}", 0)
  end
  print(string.format("变更%d次后统计:    %d hits, %d misses (re-match overhead)",
    changes, _G.exp06.metrics.hits, _G.exp06.metrics.misses))

  print("")
  print("=== 指标总结 ===")
  print(string.format("  命中率: %.1f%% (warm cache)", hit_rate))
  print(string.format("  加速比: %.1fx", speedup))
  print(string.format("  变更后重建开销: 每次失效触发 %d 次 miss 后恢复命中", changes))
end

-- === 主演示 ===
local cwd = vim.fn.getcwd()
vim.opt.rtp:prepend(cwd)
vim.cmd('runtime! plugin/*.lua plugin/*.vim')
require("codediff").setup()

local lines = {
  "function first() {",
  "  return 1",
  "}",
  "",
  "function second() {",
  "  return 2",
  "}",
}
_G.exp06.bufnr = vim.api.nvim_create_buf(true, true)
vim.api.nvim_buf_set_lines(_G.exp06.bufnr, 0, -1, false, lines)
vim.api.nvim_buf_set_name(_G.exp06.bufnr, "%")
vim.api.nvim_set_current_buf(_G.exp06.bufnr)

print("=== 创建buffer: % (universe-path命名) ===")
print("内容: 2个function块")
for _, line in ipairs(lines) do
  print("  " .. line)
end

-- Step 1: 初始匹配，展示缓存未命中
local s, e, cached = _G.exp06.get_match(_G.exp06.bufnr, "{", "}", 0)
print(string.format("\n[Step 1] 首次匹配 [0] {%d..%d} 缓存=%s", s, e, cached))

-- Step 2: 再次匹配，展示缓存命中
s, e, cached = _G.exp06.get_match(_G.exp06.bufnr, "{", "}", 0)
print(string.format("[Step 2] 再次匹配 [0] {%d..%d} 缓存=%s (命中!)", s, e, cached))

-- Step 3: 展示第二个块
s, e, cached = _G.exp06.get_match(_G.exp06.bufnr, "{", "}", 1)
print(string.format("[Step 3] 索引[1]   {%d..%d} 缓存=%s", s, e, cached))

print(string.format("\n当前指标: %d hits, %d misses",
  _G.exp06.metrics.hits, _G.exp06.metrics.misses))

print("\n>>> 现在执行基准测试:")
print("  :lua _G.exp06.benchmark()")
print("\n>>> 或手动验证缓存失效:")
print("  1. 修改buffer: :call append(1, '  local x = 1')")
print("  2. 查询验证: :lua local s,e,c = _G.exp06.get_match(0, '{', '}', 0); print(string.format('{%d..%d} cached=%s', s, e, c))")
