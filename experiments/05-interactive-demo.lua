-- Experiment 05: Buffer命名方案 + filetype高亮验证
-- 运行: nvim 然后 :source experiments/05-interactive-demo.lua
-- 验证: universe-path 命名在 scratch(nofile) buffer 下是否影响显式 filetype
--       以及 buffer 名称是否完整保留
-- 使用方法:
--   :lua _G.exp05.run_all()      — 运行全部
--   :lua _G.exp05.inspect(n)     — 打开第n个buffer交互检查语法高亮

_G.exp05 = {}

-- === Caseenv（环境 — 命名格式 × 代码类型 × buffer类型） ===

_G.exp05.caseenvs = {
  {
    name = "cf_plain_lua",
    desc = "lua 普通文件名",
    buf_name = "test.lua",
    content_type = "lua",
    lines = { "function foo()", "  return 1 + 1", "end" },
  },
  {
    name = "cf_pattern",
    desc = "pattern %:/pattern/",
    buf_name = "%:/function foo|end/",
    content_type = "lua",
    lines = { "function foo()", "  return 1 + 1", "end" },
  },
  {
    name = "cf_range",
    desc = "行号 %:1-3",
    buf_name = "%:1-3",
    content_type = "lua",
    lines = { "function foo()", "  return 1 + 1", "end" },
  },
  {
    name = "cf_pattern_mod",
    desc = "pattern+modifier %:/pat/-modified",
    buf_name = "%:/function foo|end/-modified",
    content_type = "lua",
    lines = { "function foo()", "  return 1 + 1", "end" },
  },
  {
    name = "cf_nested",
    desc = "嵌套路径 %:/dir/file.ext:1-10",
    buf_name = "%:/src/utils.lua:1-10",
    content_type = "lua",
    lines = { "function foo()", "  return 1 + 1", "end" },
  },
  {
    name = "cf_noext",
    desc = "无扩展名 %:/block/",
    buf_name = "%:/block/",
    content_type = "lua",
    lines = { "function foo()", "  return 1 + 1", "end" },
  },
  {
    name = "cf_weird",
    desc = "特殊字符 %:/foo|bar:1-5/-mod",
    buf_name = "%:/foo|bar:1-5/-modified",
    content_type = "lua",
    lines = { "function foo()", "  return 1 + 1", "end" },
  },
  {
    name = "cf_py",
    desc = "python + pattern",
    buf_name = "%:/def foo|return/",
    content_type = "python",
    lines = { "def foo():", "    return 1 + 1" },
  },
  {
    name = "cf_js",
    desc = "javascript + pattern",
    buf_name = "%:/function foo|return/",
    content_type = "javascript",
    lines = { "function foo() {", "  return 1 + 1;", "}" },
  },
  {
    name = "cf_listed_lua",
    desc = "listed buffer（基准：自动检测）",
    buf_name = "test.lua",
    content_type = "auto",
    buftype = "",
    lines = { "function foo()", "  return 1 + 1", "end" },
  },
  {
    name = "cf_listed_py",
    desc = "listed buffer python自动检测",
    buf_name = "test.py",
    content_type = "auto",
    buftype = "",
    lines = { "def foo():", "    return 1 + 1" },
  },
}

-- === Case（机制验证） ===

_G.exp05.cases = {
  {
    id = "filetype_settable",
    desc = "设filetype后值不被覆盖",
    run = function(bufnr, env, result)
      local expected = env.content_type
      if expected == "auto" then
        -- listed buffer with extension: check auto-detection
        local ft = vim.bo[bufnr].filetype
        local ok = ft ~= nil and ft ~= ""
        if not ok then
          table.insert(result.errors, string.format("listed buffer自动检测失败 (name=%s)", env.buf_name))
        else
          result.counts.ft_settable = (result.counts.ft_settable or 0) + 1
          result.filetype = ft
        end
      else
        local ft = vim.bo[bufnr].filetype
        if ft ~= expected then
          table.insert(result.errors, string.format("filetype错误: 期望%s 实际%s (name=%s)", expected, ft or "nil", env.buf_name))
        else
          result.counts.ft_settable = (result.counts.ft_settable or 0) + 1
          result.filetype = ft
        end
      end
    end,
  },
  {
    id = "syntax_loaded",
    desc = "设置:file后syntax不被清除",
    run = function(bufnr, env, result)
      -- 强制加载 syntax
      pcall(vim.cmd, "runtime! syntax/" .. (vim.bo[bufnr].filetype or "lua") .. ".vim")
      local syn = vim.bo[bufnr].syntax
      if syn ~= nil and syn ~= "" then
        result.counts.syntax_loaded = (result.counts.syntax_loaded or 0) + 1
      end
    end,
  },
}

-- === 运行引擎 ===

function _G.exp05.run_all()
  _G.exp05.results = {}

  print("")
  print("=== Experiment 05: Buffer命名 + filetype高亮 ===")
  print(string.format("%d 命名方案 × %d 验证项", #_G.exp05.caseenvs, #_G.exp05.cases))
  print("")

  local passed, failed = 0, 0

  for _, env in ipairs(_G.exp05.caseenvs) do
    local is_listed = (env.buftype ~= nil and env.buftype == "")
    local bufnr = vim.api.nvim_create_buf(is_listed, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, env.lines)

    if env.buftype ~= nil then
      vim.bo[bufnr].buftype = env.buftype
    end

    -- 设置 buffer 名称（nofile buffer 路径会展开，这是 nvim 行为）
    vim.api.nvim_buf_set_name(bufnr, env.buf_name)

    local result = {
      env_name = env.name,
      env_desc = env.desc,
      buf_name = env.buf_name,
      actual_name = vim.api.nvim_buf_get_name(bufnr),
      is_listed = is_listed,
      counts = {},
      errors = {},
    }

    -- 显式设置 filetype（nofile buffer 必须显式设）
    if env.content_type ~= "auto" then
      vim.bo[bufnr].filetype = env.content_type
    end

    -- 模拟 codediff 的 :file 触发步骤
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("doautocmd BufRead")
    end)

    for _, case in ipairs(_G.exp05.cases) do
      case.run(bufnr, env, result)
    end

    -- 名称保留性：关键断言——实际命名必须包含原始前缀%字符
    local has_pct = result.actual_name:find("%", 1, true) ~= nil
    result.name_preserved_prefix = has_pct

    local nerr = #result.errors
    if nerr == 0 then
      passed = passed + 1
      print(string.format("  [PASS] %-24s %s  ft=%s", env.name, env.desc, result.filetype or "?"))
    else
      failed = failed + 1
      print(string.format("  [FAIL] %-24s %s — %d errors", env.name, env.desc, nerr))
      for _, err in ipairs(result.errors) do
        print(string.format("         -> %s", err))
      end
    end

    _G.exp05.results[#_G.exp05.results + 1] = result
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end

  print("")
  _G.exp05.print_summary(passed, failed)
  return { passed = passed, failed = failed }
end

function _G.exp05.print_summary(passed, failed)
  local total = passed + failed
  print("=== 验证指标 ===")
  print(string.format("  命名方案:      %d/%d PASS (%.0f%%)", passed, total, passed / total * 100))

  -- 统计各命名类型的名称保留性
  local kept, expanded = 0, 0
  for _, r in ipairs(_G.exp05.results) do
    if r.name_preserved_prefix then kept = kept + 1 else expanded = expanded + 1 end
  end
  print(string.format("  名称前缀保留:  %d/%d", kept, #_G.exp05.results))

  -- 分隔符（|:-/）在命名中是否引起问题
  local special_ok = true
  local special_chars = { "|", ":", "-", "/", "%" }
  for _, r in ipairs(_G.exp05.results) do
    for _, ch in ipairs(special_chars) do
      if string.find(r.buf_name, ch, 1, true) and #r.errors > 0 then special_ok = false end
    end
  end
  print(string.format("  特殊字符兼容:  %s", special_ok and "正常" or "有问题"))

  -- 跨语言
  local lang_counts = {}
  for _, r in ipairs(_G.exp05.results) do
    local ft = r.filetype or "unknown"
    lang_counts[ft] = (lang_counts[ft] or 0) + 1
  end
  local langs = {}
  for k, v in pairs(lang_counts) do langs[#langs + 1] = string.format("%s=%d", k, v) end
  print(string.format("  filetype覆盖:   %s", table.concat(langs, ", ")))
end

function _G.exp05.summary()
  if not _G.exp05.results or #_G.exp05.results == 0 then
    print("No results yet. Run :lua _G.exp05.run_all() first.")
    return
  end
  local passed, failed = 0, 0
  for _, r in ipairs(_G.exp05.results) do
    if #r.errors == 0 then passed = passed + 1 else failed = failed + 1 end
  end
  _G.exp05.print_summary(passed, failed)
end

-- === 交互式检查 ===

function _G.exp05.inspect(env_index)
  local env = _G.exp05.caseenvs[env_index]
  if not env then
    print("Invalid index. Available:")
    for i, e in ipairs(_G.exp05.caseenvs) do
      print(string.format("  %d: %s (%s)", i, e.name, e.desc))
    end
    return
  end

  local is_listed = (env.buftype ~= nil and env.buftype == "")
  local bufnr = vim.api.nvim_create_buf(is_listed, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, env.lines)
  if env.buftype ~= nil then vim.bo[bufnr].buftype = env.buftype end
  vim.api.nvim_buf_set_name(bufnr, env.buf_name)
  if env.content_type ~= "auto" then vim.bo[bufnr].filetype = env.content_type end
  vim.api.nvim_buf_call(bufnr, function() vim.cmd("doautocmd BufRead") end)
  vim.api.nvim_set_current_buf(bufnr)

  print(string.format(">>> Buffer: %s", env.buf_name))
  print(string.format("    实际路径: %s", vim.api.nvim_buf_get_name(bufnr)))
  print(string.format("    filetype: '%s'", vim.bo[bufnr].filetype))
  print(string.format("    syntax:   '%s'", vim.bo[bufnr].syntax))
  print(string.format("    buftype:  '%s'", vim.bo[bufnr].buftype))
  _G.exp05.inspect_buf = bufnr
end

-- === Setup ===
local cwd = vim.fn.getcwd()
vim.opt.rtp:prepend(cwd)
vim.cmd('runtime! plugin/*.lua plugin/*.vim')
require("codediff").setup()

print("=== Experiment 05: Buffer命名 + filetype高亮 ===")
print(string.format("%d 命名方案（universe-path × 跨语言 × listed/nofile）", #_G.exp05.caseenvs))
print("")
print(">>> 运行:")
print("  :lua _G.exp05.run_all()     — 批量验证")
print("  :lua _G.exp05.inspect(n)    — 打开buffer交互查看语法高亮")