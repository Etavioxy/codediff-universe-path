-- Experiment 06 交互式演示：Realtime Rematching
-- 运行: nvim 然后 :source experiments/06-interactive-demo.lua
-- 验证：缓存命中/失效 + 文件修改后重新匹配

_G.exp06 = {}
_G.exp06.cache = {}

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
    return c.start_line, c.end_line, true
  end
  local start_line, end_line = _G.exp06.match_and_cache(bufnr, s, e, idx)
  return start_line, end_line, false
end

-- 主演示
local cwd = vim.fn.getcwd()
vim.opt.rtp:prepend(cwd)
vim.cmd('runtime! plugin/*.lua plugin/*.vim')
require("codediff").setup()

-- 初始化原文件buffer
local lines = {
  "function first() {",
  "  return 1",
  "}",
  "",
  "function second() {",
  "  return 2",
  "}",
}
local bufnr = vim.api.nvim_create_buf(true, true)
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
vim.api.nvim_buf_set_name(bufnr, "%")
vim.api.nvim_set_current_buf(bufnr)

print("=== 创建buffer: % (universe-path命名) ===")
print("内容: 2个function块")

-- Step 1: 初始匹配，展示缓存未命中
local s, e, cached = _G.exp06.get_match(bufnr, "{", "}", 0)
print(string.format("[0] {%s..%s} 缓存=%s — 第一次匹配，缓存为false", s, e, cached))

-- Step 2: 再次匹配，展示缓存命中
s, e, cached = _G.exp06.get_match(bufnr, "{", "}", 0)
print(string.format("[0] {%s..%s} 缓存=%s — 第二次匹配，缓存为true（命中！）", s, e, cached))

-- 展示第二个块
s, e, cached = _G.exp06.get_match(bufnr, "{", "}", 1)
print(string.format("[1] {%s..%s} 缓存=%s", s, e, cached))

print("")
print(">>> 现在将修改buffer内容，验证缓存失效 + 重新匹配 <<<")
print(">>> 按任意键继续，或保持查看buffer <<<")
