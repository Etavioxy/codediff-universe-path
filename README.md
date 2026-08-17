# codediff-universe-path

English | [中文](README.zh.md)

When an AI agent finishes a change, it knows more about the impact than any diff dump can show. What matters is the **blast radius** — the ripple of that change through the codebase: which functions moved, which blocks shifted, which callers are affected. This plugin gives that knowledge a language: universe-path, a compact notation that points at exactly the changed ranges — lines, blocks, functions — in the current file or at any VCS revision. The agent summarizes a commit's blast radius in universe-path; you open the result and see the scoped diff rendered with VSCode-style two-tier highlighting, side-by-side or inline. Diff by meaning, not by file.

![VSCode-style diff view showing side-by-side comparison with two-tier highlighting](https://github.com/user-attachments/assets/473ae319-40ac-40e4-958b-a0f2525d1f94)

## Introduction

codediff-universe-path is a fork of [esmuellert/codediff.nvim](https://github.com/esmuellert/codediff.nvim). It keeps the complete upstream feature set — VSCode-style diff rendering driven by a C port of VSCode's own diff engine — and layers a new way to address precise text ranges on top of it.

**This fork: Universe Path.** Universe Path Syntax is a compact notation — `[VCS:version@]path[:locator][modifiers]` — for pointing at an exact text range (lines, blocks, regex matches) in the current file or at any VCS revision:

```
%                       → the current file
%:45-120                → lines 45–120 of the current file
%:/{|}/                 → the current brace block
git:HEAD~3@%:/{|}/+3^   → the current block plus 3 lines above, at git HEAD~3
```

It solves "diff exactly this function / block / range" without opening the whole file. The full grammar and every example live in [docs/universe-path/spec.md](docs/universe-path/spec.md). Universe Path is the active development direction of this fork.

## Features

- **Two-tier highlighting**: light backgrounds for whole modified lines (green insertions / red deletions) plus deep character-level highlights for exact in-line changes
- **Side-by-side diff view** in a new tab with synchronized scrolling
- **Inline (unified) diff view**: single window, deleted lines as virtual overlays, with treesitter highlighting
- **Toggle layout** at runtime with `t`
- **Git integration**: compare any git revision (HEAD, commits, branches, tags)
- **Same implementation as VSCode's diff engine**, giving identical visual highlighting in most scenarios
- **Fast C-based diff computation** via FFI with **multi-core parallelization** (OpenMP)
- **Async git operations** — non-blocking file retrieval from git
- **Moved code detection** (opt-in, matches VSCode's experimental `showMoves`)

## Installation

### Prerequisites

- Neovim >= 0.7.0 (for Lua FFI support; 0.10+ recommended for `vim.system`)
- Git (for git diff features)
- `curl` or `wget` (for automatic binary download)

**No compiler required!** The plugin downloads pre-built binaries from GitHub releases automatically.

### lazy.nvim

```lua
{
  "Etavioxy/codediff-universe-path",
  cmd = "CodeDiff",
}
```

The plugin adapts to your colorscheme's background automatically: it uses `DiffAdd`/`DiffDelete` for line-level diffs and auto-adjusts character-level brightness (1.4x brighter for dark themes, 0.92x darker for light themes). See [Highlight Groups](#highlight-groups).

### Manual (git clone)

```bash
git clone https://github.com/Etavioxy/codediff-universe-path ~/.local/share/nvim/codediff-universe-path
```

Add to `init.lua`: `vim.opt.rtp:append("~/.local/share/nvim/codediff-universe-path")`. Then install the C library — either run `:CodeDiff install` (auto-download) or build from source:

```bash
./build.sh            # Linux/macOS/BSD
build.cmd             # Windows
```

The C library auto-downloads on first use and auto-updates with the plugin; `:CodeDiff install!` forces a reinstall.

## Configuration

```lua
{
  "Etavioxy/codediff-universe-path",
  cmd = "CodeDiff",
  opts = {
    -- Highlights: highlight group names or hex colors (e.g. "#2ea043")
    highlights = {
      line_insert = "DiffAdd", line_delete = "DiffDelete",   -- line-level
      char_insert = nil, char_delete = nil,                  -- char-level (nil = derive)
      char_brightness = nil,                                 -- nil = auto (1.4 dark / 0.92 light)
      conflict_sign = nil, conflict_sign_resolved = nil,
      conflict_sign_accepted = nil, conflict_sign_rejected = nil,
    },
    diff = {
      layout = "side-by-side",             -- "side-by-side" | "inline"
      disable_inlay_hints = true, max_computation_time_ms = 5000,
      ignore_trim_whitespace = false,      -- like diffopt+=iwhite
      hide_merge_artifacts = false,        -- hide *.orig, *.BACKUP.*, ...
      original_position = "left",          -- "left" | "right"
      conflict_ours_position = "right",
      conflict_result_position = "bottom", -- "bottom" | "center"
      conflict_result_height = 30, conflict_result_width_ratio = { 1, 1, 1 },
      cycle_next_hunk = true, cycle_next_file = true,        -- wrap ]c/[c, ]f/[f
      jump_to_first_change = true, highlight_priority = 100,
      compute_moves = false,               -- moved code detection (opt-in)
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
        diff_get = "do", diff_put = "dp", open_in_prev_tab = "gf", close_on_open_in_prev_tab = false, -- do/dp like vimdiff
        toggle_stage = "-", stage_hunk = "<leader>hs", unstage_hunk = "<leader>hu", discard_hunk = "<leader>hr",
        hunk_textobject = "ih", show_help = "g?", align_move = "gm", toggle_layout = "t",
      },
      explorer = {
        select = "<CR>", hover = "K", refresh = "R",
        toggle_view_mode = "i", stage_all = "S", unstage_all = "U", restore = "X",
        toggle_changes = "gu", toggle_staged = "gs",
        -- Vim-style fold maps: zo, zO, zc, zC, za, zA, zR, zM
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

## Usage

The `:CodeDiff` command supports multiple modes.

```vim
" File Explorer Mode
:CodeDiff                          " git status explorer (default)
:CodeDiff HEAD~5                   " changes for a revision
:CodeDiff main                     " against a branch
:CodeDiff abc123                   " against a commit
:CodeDiff main HEAD                " two revisions
:CodeDiff --inline | --side-by-side  " layout override (all subcommands)
" PR-like diff (merge-base)
:CodeDiff main...                  " merge-base(main, HEAD) vs working tree
:CodeDiff main...HEAD              " merge-base(main, HEAD) vs HEAD
:CodeDiff develop...feature/new-ui
" Git Diff Mode (current file vs revision)
:CodeDiff file HEAD                " also HEAD~1, abc123, main, v1.0.0
:CodeDiff file main HEAD           " two revisions for current file
:CodeDiff file main...             " merge-base vs working tree
" File / Directory Comparison
:CodeDiff file file_a.txt file_b.txt   " compare two files
:CodeDiff ~/project-v1 ~/project-v2     " compare two directories
:CodeDiff dir /path/to/dir1 /path/to/dir2
" File History Mode
:CodeDiff history                  " last 50 commits
:CodeDiff history HEAD~10          " last N commits
:CodeDiff history origin/main..HEAD  " range (PR review)
:CodeDiff history HEAD~20 %        " current file only
:CodeDiff history --reverse        " oldest first
:CodeDiff history --base WORKING   " each commit vs working tree
:'<,'>CodeDiff history             " commits touching selected lines
```

### Git Merge / Diff Tool

```bash
git config --global merge.tool codediff
git config --global mergetool.codediff.cmd 'nvim "$MERGED" -c "CodeDiff merge \"$MERGED\""'

git config --global diff.tool codediff
git config --global difftool.codediff.cmd 'nvim "$LOCAL" "$REMOTE" +"CodeDiff file $LOCAL $REMOTE"'
```

Then use `git difftool` (optionally `git difftool -y`).

## Highlight Groups

- `CodeDiffLineInsert` — light green background for inserted lines
- `CodeDiffLineDelete` — light red background for deleted lines
- `CodeDiffCharInsert` — deep green for inserted characters
- `CodeDiffCharDelete` — deep red for deleted characters
- `CodeDiffFiller` — gray foreground for filler line slashes (`╱╱╱`)
- `CodeDiffLineMove` — background for moved code lines (derived from `DiffChange`)
- `CodeDiffMoveTo` — sign column / annotation color for move indicators

By default line-level highlights use your colorscheme's `DiffAdd`/`DiffDelete`, and character-level highlights auto-adjust to `vim.o.background`. Override with group names or hex colors:

```lua
highlights = {
  line_insert = "#1d3042",
  line_delete = "#351d2b",
  char_brightness = 1.5,   -- override auto-detection
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

-- Advanced: direct access to internal modules
local diff = require("codediff.diff")
local git = require("codediff.git")
local lines_diff = diff.compute_diff({"line 1", "line 2"}, {"line 1", "modified line 2"})
git.get_file_content("HEAD~1", "/path/to/repo", "relative/path.lua", function(err, lines) end)
```

**User autocmd events:** `CodeDiffOpen`, `CodeDiffClose`, `CodeDiffFileSelect` are emitted as `User` events (`mode` is `"explorer"`, `"standalone"`, or `"history"`).

## Development

```bash
make clean && make   # build
make test            # all tests (C + Lua integration)
make test-c          # C unit tests only
make test-lua        # Lua integration tests only
```

See [tests/README.md](tests/README.md). The C diff engine lives in `libvscode-diff/`, the Lua modules in `lua/codediff/`.

## License

MIT — see [LICENSE](LICENSE). This project is a fork of [esmuellert/codediff.nvim](https://github.com/esmuellert/codediff.nvim) (MIT). The C diff engine is a port of VSCode's algorithm; bundled and derived components (VSCode, utf8proc, Neovim LSP, and others) carry their own licenses — see [ATTRIBUTION.md](ATTRIBUTION.md).

## Contributing

Contributions are welcome! Please ensure C tests and Lua tests pass (`make test`) and code follows the existing style.
