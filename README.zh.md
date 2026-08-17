# codediff-universe-path

[English](README.md) | 中文

当 AI agent 完成一次改动，它对影响范围的了解远超任何 diff 转储所能展示的。真正重要的是 **blast radius**——这次改动在代码库中的波及范围：哪些函数移动了、哪些块错位了、哪些调用方受影响。这个插件给这种理解一种语言：universe-path，一种紧凑的记法，精确定位发生变更的范围——行、块、函数——在当前文件或任意 VCS 版本中。agent 用 universe-path 总结一次提交的 blast radius；你打开结果，看到以 VSCode 风格两级高亮渲染的、按语义裁剪的 diff，并排或内联。按语义看 diff，而非按文件。

![VSCode 风格 diff 视图，展示并排比较与两级高亮](https://github.com/user-attachments/assets/473ae319-40ac-40e4-958b-a0f2525d1f94)

## 简介

codediff-universe-path 是 [esmuellert/codediff.nvim](https://github.com/esmuellert/codediff.nvim) 的一个 fork。它保留了上游的完整功能集——由 VSCode 自家 diff 引擎的 C 移植版本驱动的 VSCode 风格 diff 渲染——并在此之上叠加了一种定位精确文本范围的新方式。

**本 fork：Universe Path。** Universe Path 语法是一种紧凑的记法——`[VCS:版本@]路径[:定位器][修饰器]`——用于指向当前文件或任意 VCS 版本中的精确文本范围（行、代码块、正则匹配）：

```
%                       → 当前文件
%:45-120                → 当前文件第 45–120 行
%:/{|}/                 → 当前大括号块
git:HEAD~3@%:/{|}/+3^   → 当前块 + 向上 3 行，位于 git HEAD~3
```

它解决了"只 diff 这一个函数 / 代码块 / 范围"而无需打开整个文件的问题。完整语法与全部示例见 [docs/universe-path/spec.md](docs/universe-path/spec.md)。Universe Path 是本 fork 的活跃开发方向。

## 功能特性

- **两级高亮**：整行修改使用浅色背景（插入绿色 / 删除红色），并对行内精确改动做深色字符级高亮
- **并排 diff 视图**：在新标签页中展示，支持同步滚动
- **内联（unified）diff 视图**：单窗口，删除的行以虚拟覆盖层展示，带 treesitter 高亮
- **运行时切换布局**：按 `t` 切换
- **Git 集成**：比较任意 git 版本（HEAD、提交、分支、标签）
- **与 VSCode diff 引擎相同实现**，在多数场景下提供一致的视觉高亮
- **基于 C 的快速 diff 计算**，通过 FFI 实现，支持**多核并行**（OpenMP）
- **异步 git 操作**——从 git 非阻塞地读取文件
- **移动代码检测**（需主动开启，匹配 VSCode 实验性 `showMoves`）

## 安装

### 前置条件

- Neovim >= 0.7.0（用于 Lua FFI；推荐 0.10+ 以使用 `vim.system`）
- Git（用于 git diff 功能）
- `curl` 或 `wget`（用于自动下载二进制）

**无需编译器！** 插件会自动从 GitHub releases 下载预编译二进制。

### lazy.nvim

```lua
{
  "Etavioxy/codediff-universe-path",
  cmd = "CodeDiff",
}
```

插件会自动适配你的配色方案背景：行级 diff 使用 `DiffAdd`/`DiffDelete`，并自动调整字符级亮度（暗色主题 1.4 倍变亮，亮色主题 0.92 倍变暗）。见 [高亮组](#高亮组)。

### 手动安装（git clone）

```bash
git clone https://github.com/Etavioxy/codediff-universe-path ~/.local/share/nvim/codediff-universe-path
```

在 `init.lua` 中加入：`vim.opt.rtp:append("~/.local/share/nvim/codediff-universe-path")`。然后安装 C 库——运行 `:CodeDiff install`（自动下载）或从源码构建：

```bash
./build.sh            # Linux/macOS/BSD
build.cmd             # Windows
```

C 库在首次使用时自动下载，并随插件版本自动更新；`:CodeDiff install!` 可强制重装。

## 配置

```lua
{
  "Etavioxy/codediff-universe-path",
  cmd = "CodeDiff",
  opts = {
    -- 高亮：高亮组名或十六进制颜色（如 "#2ea043"）
    highlights = {
      line_insert = "DiffAdd", line_delete = "DiffDelete",   -- 行级
      char_insert = nil, char_delete = nil,                  -- 字符级（nil = 自动推导）
      char_brightness = nil,                                 -- nil = 自动（暗 1.4 / 亮 0.92）
      conflict_sign = nil, conflict_sign_resolved = nil,
      conflict_sign_accepted = nil, conflict_sign_rejected = nil,
    },
    diff = {
      layout = "side-by-side",             -- "side-by-side" | "inline"
      disable_inlay_hints = true, max_computation_time_ms = 5000,
      ignore_trim_whitespace = false,      -- 类似 diffopt+=iwhite
      hide_merge_artifacts = false,        -- 隐藏 *.orig、*.BACKUP.* 等
      original_position = "left",          -- "left" | "right"
      conflict_ours_position = "right",
      conflict_result_position = "bottom", -- "bottom" | "center"
      conflict_result_height = 30, conflict_result_width_ratio = { 1, 1, 1 },
      cycle_next_hunk = true, cycle_next_file = true,        -- ]c/[c、]f/[f 循环
      jump_to_first_change = true, highlight_priority = 100,
      compute_moves = false,               -- 移动代码检测（需开启）
    },
    explorer = {
      position = "left",                   -- "left" | "bottom"
      width = 40, height = 15, indent_markers = true,
      initial_focus = "explorer",
      icons = { folder_closed = "", folder_open = "" },
      view_mode = "list", flatten_dirs = true,   -- "list" | "tree"
      file_filter = { ignore = { ".git/**", ".jj/**" } },
      focus_on_select = false,
      visible_groups = { staged = true, unstaged = true, conflicts = true },
    },
    history = {
      position = "bottom",                 -- "left" | "bottom"
      width = 40, height = 15, initial_focus = "history",
      view_mode = "list",                  -- "list" | "tree"
    },
    keymaps = {
      view = {
        quit = "q", toggle_explorer = "<leader>b", focus_explorer = "<leader>e",
        next_hunk = "]c", prev_hunk = "[c", next_file = "]f", prev_file = "[f",
        diff_get = "do", diff_put = "dp", open_in_prev_tab = "gf", close_on_open_in_prev_tab = false, -- do/dp 类似 vimdiff
        toggle_stage = "-", stage_hunk = "<leader>hs", unstage_hunk = "<leader>hu", discard_hunk = "<leader>hr",
        hunk_textobject = "ih", show_help = "g?", align_move = "gm", toggle_layout = "t",
      },
      explorer = {
        select = "<CR>", hover = "K", refresh = "R",
        toggle_view_mode = "i", stage_all = "S", unstage_all = "U", restore = "X",
        toggle_changes = "gu", toggle_staged = "gs",
        -- Vim 风格折叠按键：zo、zO、zc、zC、za、zA、zR、zM
      },
      history = { select = "<CR>", toggle_view_mode = "i", refresh = "R" },
      conflict = {
        accept_incoming = "<leader>ct", accept_current = "<leader>co",
        accept_both = "<leader>cb", discard = "<leader>cx",
        accept_all_incoming = "<leader>cT", accept_all_current = "<leader>cO",
        accept_all_both = "<leader>cB", discard_all = "<leader>cX",
        next_conflict = "]x", prev_conflict = "[x",
        diffget_incoming = "2do", diffget_current = "3do",
      },
    },
  },
}
```

## 用法

`:CodeDiff` 命令支持多种模式。

```vim
" 文件浏览器模式
:CodeDiff                          " 默认：git status 浏览器
:CodeDiff HEAD~5                   " 某版本的变化
:CodeDiff main                     " 对比分支
:CodeDiff abc123                   " 对比提交
:CodeDiff main HEAD                " 对比两个版本
:CodeDiff --inline | --side-by-side  " 本次调用的布局覆盖（适用于所有子命令）
" PR 式 diff（merge-base）
:CodeDiff main...                  " merge-base(main, HEAD) 对比工作区
:CodeDiff main...HEAD              " merge-base(main, HEAD) 对比 HEAD
:CodeDiff develop...feature/new-ui
" Git Diff 模式（当前文件对比版本）
:CodeDiff file HEAD                " 也可用 HEAD~1、abc123、main、v1.0.0
:CodeDiff file main HEAD           " 当前文件的两个版本
:CodeDiff file main...             " merge-base 对比工作区
" 文件 / 目录对比
:CodeDiff file file_a.txt file_b.txt   " 对比两个文件
:CodeDiff ~/project-v1 ~/project-v2     " 对比两个目录
:CodeDiff dir /path/to/dir1 /path/to/dir2
" 文件历史模式
:CodeDiff history                  " 最近 50 条提交
:CodeDiff history HEAD~10          " 最近 N 条提交
:CodeDiff history origin/main..HEAD  " 范围（适合 PR 审查）
:CodeDiff history HEAD~20 %        " 仅当前文件
:CodeDiff history --reverse        " 正序（从旧到新）
:CodeDiff history --base WORKING   " 每条提交对比工作区
:'<,'>CodeDiff history             " 影响所选行的提交
```

### Git 合并 / Diff 工具

```bash
git config --global merge.tool codediff
git config --global mergetool.codediff.cmd 'nvim "$MERGED" -c "CodeDiff merge \"$MERGED\""'

git config --global diff.tool codediff
git config --global difftool.codediff.cmd 'nvim "$LOCAL" "$REMOTE" +"CodeDiff file $LOCAL $REMOTE"'
```

然后使用 `git difftool`（可选 `git difftool -y`）。

## 高亮组

- `CodeDiffLineInsert` —— 插入行的浅绿色背景
- `CodeDiffLineDelete` —— 删除行的浅红色背景
- `CodeDiffCharInsert` —— 插入字符的深绿色
- `CodeDiffCharDelete` —— 删除字符的深红色
- `CodeDiffFiller` —— 填充行斜杠（`╱╱╱`）的灰色前景
- `CodeDiffLineMove` —— 移动代码行的背景（派生自 `DiffChange`）
- `CodeDiffMoveTo` —— 移动指示符的 sign 列 / 注释颜色

默认行级高亮使用配色方案的 `DiffAdd`/`DiffDelete`，字符级高亮自动适配 `vim.o.background`。可用高亮组名或十六进制颜色覆盖：

```lua
highlights = {
  line_insert = "#1d3042",
  line_delete = "#351d2b",
  char_brightness = 1.5,   -- 覆盖自动检测
}
```

## Lua API

```lua
require("codediff").setup({
  highlights = {
    line_insert = "DiffAdd",
    line_delete = "DiffDelete",
    char_brightness = 1.4,
  },
})

-- 进阶：直接访问内部模块
local diff = require("codediff.diff")
local git = require("codediff.git")
local lines_diff = diff.compute_diff({"line 1", "line 2"}, {"line 1", "modified line 2"})
git.get_file_content("HEAD~1", "/path/to/repo", "relative/path.lua", function(err, lines) end)
```

**用户 autocmd 事件：** `CodeDiffOpen`、`CodeDiffClose`、`CodeDiffFileSelect` 以 `User` 事件发出（`mode` 为 `"explorer"`、`"standalone"` 或 `"history"`）。

## 开发

```bash
make clean && make   # 构建
make test            # 全部测试（C + Lua 集成）
make test-c          # 仅 C 单元测试
make test-lua        # 仅 Lua 集成测试
```

见 [tests/README.md](tests/README.md)。C diff 引擎位于 `libvscode-diff/`，Lua 模块位于 `lua/codediff/`。

## 许可证

MIT——见 [LICENSE](LICENSE)。本项目是 [esmuellert/codediff.nvim](https://github.com/esmuellert/codediff.nvim)（MIT）的 fork。C diff 引擎是 VSCode 算法的移植；打包与派生的组件（VSCode、utf8proc、Neovim LSP 等）遵循各自许可证——见 [ATTRIBUTION.md](ATTRIBUTION.md)。

## 贡献

欢迎贡献！请确保 C 测试与 Lua 测试通过（`make test`），且代码遵循现有风格。
