# Universe Path Experiments

## 实验列表

| 编号 | 实验名称 | 描述 |
|------|----------|------|
| 01-nested-bracket-matching | 贪心vs嵌套匹配算法验证 | 验证两种匹配模式差异 |
| 02-buffer-view-create-integration | buffer填充后调用codediff.view.create渲染diff | 整个流程串联点，最关键 |
| 03-index-semantic-validation | 嵌套{}下索引正确性及倒序[-N]反向扫描 | 两个测试环境：正常+失配 |
| 04-buffer-preparation-bypass | 绕过prepare_buffer直接填充buffer | codediff.nvim内部流程兼容性 |
| 05-virtual-buffer-naming-scheme | buffer命名方案影响filetype高亮 | 文本片段buffer如何命名 |
| 06-realtime-rematching | 文件改动后重新匹配机制 | 缓存失效策略和重新匹配时机 |
| 07-buffer-writeback | buffer保存时写回原文件 | 写回前检测变动、写回后重新定位 |

## 完成状态

- 01: 已完成
  - 遗漏：同一行多个括号的精确位置返回（只返回行号，无列号）

- 02: 已完成
  - 遗漏：未验证diff高亮是否实际渲染
  - 遗漏：未验证filetype高亮是否正确
  - 疑虑：inline模式是否同样可行

- 03: 已完成
  - 性能问题：倒序索引必须遍历全部文件
  - 设计决策：失配只检测当前块范围内
  - 疑虑：复杂跨行嵌套未测试

- 06: 已完成
  - 交互式脚本：experiments/06-interactive-demo.lua（_G.exp06 全局可查询）
  - 架构：20 caseenv（环境）x 5 case（缓存机制）验证矩阵
  - 环境：12 normal + 3 mismatch + 5 mutation，手写17 + 生成3（500行/100块/10层嵌套）
  - 录制demo：exp06-demo.cast（157组合验证，20/20 PASS，100%正确率）
  - 机制：首次miss / 再次hit / 无误失效 / 突变miss / 重匹配一致 / 失配安全
  - 遗漏：未测试TextChanged autocmd实际监听
  - 遗漏：未测试并发修改场景

- 07: 已完成
  - 交互式脚本：experiments/07-interactive-demo.lua（_G.exp07 全局可查询）
  - 录制demo：exp07-demo.cast（提取→nvim中可视编辑→写回成功→外部修改拒绝→:buffers验证）
  - 编辑过程在nvim中逐步交互（extract→可视编辑→writeback 分步执行）
  - 遗漏：未测试行数变化后的区间重新定位精确性
  
- 04: 未实现
- 05: 未实现
