# Universe Path Experiments

## 实验列表

| 编号 | 实验名称 | 描述 |
|------|----------|------|
| 01-nested-bracket-matching | 贪心vs嵌套匹配算法验证 | 验证两种匹配模式差异 |
| 02-buffer-view-create-integration | buffer填充后调用codediff.view.create渲染diff | 整个流程串联点，最关键 |
| 03-index-semantic-validation | 嵌套{}下索引正确性及倒序[-N]反向扫描 | 三个测试环境：正常+失配+复杂跨行嵌套 |
| 05-virtual-buffer-naming-scheme | buffer命名方案影响filetype高亮 | 文本片段buffer如何命名 |
| 06-realtime-rematching | 文件改动后重新匹配机制 | caseenv × case 验证矩阵，缓存失效策略 |
| 07-buffer-writeback | buffer保存时写回原文件 | 写回前检测变动、写回后重新定位、行数变化测试 |

## 完成状态

- 01: 已完成
  - 遗漏：同一行多个括号的精确位置返回（只返回行号，无列号）[低优先级]

- 02: 已完成
  - 修复：filetype 语法高亮验证 — `view.create()` 对 scratch buffer 不自动设置 filetype，需要手动 `vim.bo[buf].filetype = ft`
  - 修复：diff 高亮渲染验证 — 通过 extmarks 检查确认渲染
  - 修复：inline 模式验证 — 不崩溃、高亮正常
  - 录制demo：exp02-demo.cast（side-by-side diff高亮→lua+python filetype→inline模式）

- 03: 已完成
  - 算法：栈式嵌套匹配算法（nested_match），统计所有块含嵌套，替代旧版仅顶层的计数
  - 算法：倒序扫描（reverse_nested_match），基于 total_count - N + 1 查找
  - 修复：复杂跨行嵌套数据驱动测试框架（环境3），57 项断言全部通过
  - 修复：中文注释中的 `}` 字面字符导致栈下溢（line 229，改为 `两个右括号在同一行`）
  - 录制demo：exp03-demo.cast（3 环境 × 57 断言全 PASS）
  - 性能问题：倒序索引必须遍历全部文件
  - 设计决策：失配只检测当前块范围内

- 05: 已完成
  - 交互式脚本：experiments/05-interactive-demo.lua（_G.exp05 全局可查询）
  - 5 种 universe-path 命名方案（pattern/range/modifier/nested/noext）
  - 验证：codediff side-by-side diff 视图中 winbar 完整显示命名
  - 录制demo：exp05-demo.cast（打开diff→:buffers查看→逐一切换5种命名→winbar确认）
  - :buffers 列表中 universe-path 名称（含 |:-/% 特殊字符）完整保留

- 06: 已完成
  - 交互式脚本：experiments/06-interactive-demo.lua（_G.exp06 全局可查询）
  - 架构：21 caseenv（环境）× 8 case（缓存机制）验证矩阵
  - 环境：12 normal + 3 mismatch + 5 mutation + 1 autocmd，手写18 + 生成3（500行/25块/10层嵌套）
  - 修复：post-mutation loop 中 `case_applies_to()` 检查（commit f5a0dc4），mutation case 不再在 non-mutation 环境中误跑
  - 修复：缓存失效机制 — `nvim_buf_set_lines` 不触发 TextChanged autocmd（Neovim 文档确认），改用 changedtick 检测
  - 录制demo：exp06-demo.cast（21/21 PASS，100%正确率，160 组合验证）
  - 机制覆盖：首次miss / 再次hit / 无误失效 / 突变miss / 重匹配一致 / 失配安全 / TextChanged未触发(预期) / API重匹配一致
  - 未测试：并发修改场景 [低优先级]

- 07: 已完成
  - 交互式脚本：experiments/07-interactive-demo.lua（_G.exp07 全局可查询）
  - 录制demo：exp07-demo.cast（提取→nvim中可视编辑→写回成功→外部修改拒绝→5项行数变化重定位测试）
  - 编辑过程在nvim中逐步交互（extract→可视编辑→writeback 分步执行）
  - 修复：行数变化后区间重新定位精确性 — 5 项测试（增行/删行/完全改写/缩减为单行/写回后重提取）
  - 修复：buffer 命名冲突 — `extract_range` 使用 `pcall` 处理重名 buffer，回退到唯一后缀

