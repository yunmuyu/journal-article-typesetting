# 单栏表、公式制表位和标题层级修复候选

本轮只提交开发候选，不合并正式版。不包含真实 Word、图件、字体、INDD、测量原始数据或本机配置。

## 修改与验证

- 表格列宽试排先清除旧列宽下的小数对齐缩进，避免把原本能容纳的数字误判为溢出。完成列宽选择后，由现有调用方重新计算小数对齐。
- 纯数字单元格中的分组空格保留，文字范围禁止断行；宽度不够时让原生溢出检查拒绝候选，不拆开小数末位。
- 显示公式段落缺少制表位时，根据实际单栏宽度补建居中和右对齐制表位；已有制表位保持原样，公式内容和字号不改。
- 装配后按源稿标题角色重新定位标题，从本篇已匹配标题的样式组解析样式 ID。缺失、歧义和写入失败显式报错。所有写入完成后再次核验名称与 ID，不以单次成功返回替代检查。

Node 回归全部通过：

```text
run_table_minimum_width_regression.cjs
run_missing_formula_tabs_regression.cjs
run_source_heading_identity_regression.cjs
run_scoped_assembly_plan_regression.cjs
run_real_formula_anchor_spacing_regression.cjs
run_review_contract_regression.cjs
```

另在 InDesign 2020 实际执行 `tests/native_source_heading_identity.jsx`：故意把一级标题套成二级标题，恢复后检查真实样式 ID、12 pt 字号及重复运行不改动。该原生测试曾发现 Node 未复现的循环记录层级串值；保留从源角色直接计算层级的值表达式后通过。测试只创建并关闭自己的合成临时文档，未关闭应用或已有文档。

原生测试执行方法（仓库根目录、PowerShell、InDesign 2020 已启动）：

```powershell
$module = Get-Content '2-导入_InDesign/journal_scoped_assembly.jsxinc' -Raw -Encoding utf8
$fixture = Get-Content 'tests/native_source_heading_identity.jsx' -Raw -Encoding utf8
$indesign = New-Object -ComObject InDesign.Application.2020
$indesign.DoScript($module + $fixture, 1246973031)
```

本机实稿已核对两篇的内容、表格与公式，并查看导出 PDF；标题问题在用户反馈后另修正并重新读取真实样式。原有前篇文字、几何和基线核对未变化。详细证据保留在私有交接记录，未入 Git。

## 边界与未通过项

- 单栏优先仍需要实际宽度与可读性检查。本轮不宣称自动候选搜索能证明某张表必定不能单栏；无溢出但中文被挤成逐字竖排的方案不能采用。
- 快速齐底能解决的小范围差异已处理；大留白、复杂分页和末页精排按用户当前分工留给人工，不宣称整篇达到出版终检。
- 既有全文检查器对部分公式编号的括号、空白仍有匹配差异；已人工核实对应编号存在，不把检查器整体报告称为通过。
- 本轮没有重新验证此前离线求解器的首页公式回排、第 18 页齐底、换栏高度误差及第二次整篇实排。它们不因本次提交自动转为通过。
- 原生标题回归通过，但提交前未为新增防护重新跑整篇装配。离线求解器仍为可选模块，本轮未修改公式转换缓存或简式转换器。
