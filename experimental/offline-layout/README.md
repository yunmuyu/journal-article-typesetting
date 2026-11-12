# 离线排版开发候选

本目录是独立实验入口，不接管生产排版，不自动修改 INDD。未证明每篇只需两次原生实排即可交付。现有生产入口和 VERSION 不变。验证范围及未通过项见 [候选说明](../../docs/releases/2026-11-12-offline-layout-candidate.md)。

## 云端数值求解入口

`Select-JournalOneShotLayout.ps1` 逐个调用 `Find-MeasuredPageWindow.ps1` 生成窗口候选，再调用 `Test-JournalLayoutRobustness.ps1` 校验误差范围。均使用 PowerShell 7，不需要 Adobe、Word、WPF 或字体文件。当前在 Windows PowerShell 7 实测；其他操作系统尚未实测，不把无平台依赖等同于已完成跨平台验收。

在仓库根目录执行，输出必须是尚不存在的文件：

```powershell
pwsh -NoProfile -File experimental/offline-layout/Select-JournalOneShotLayout.ps1 -CandidatePaths examples/offline-layout/synthetic-window.json -ReportPath candidate-result.json
```

多候选在 PowerShell 内传字符串数组 `-CandidatePaths @('candidate-a.json','candidate-b.json')`。输入文件不可在求解中变化。入口比较输入身份和完整范围，选择通过误差检查、总调整量较小的候选。这里只选择调用者提供的候选集合，不会从 Word 自动生成全部可能版式。

### 输入 JSON v1

```json
{
  "version": 1,
  "sourceIdentity": "synthetic-article",
  "startIndex": 100,
  "endIndex": 120,
  "blocks": [
    {"kind":"body","startIndex":100,"endIndex":110,"advanceMm":20,"compressMm":0,"expandMm":0,"continuationMm":0,"canBreakAfter":true,"errorBelowMm":0,"errorAboveMm":0},
    {"kind":"body","startIndex":110,"endIndex":120,"advanceMm":20,"compressMm":0,"expandMm":0,"continuationMm":0,"canBreakAfter":true,"errorBelowMm":0,"errorAboveMm":0}
  ],
  "slots": [
    {"kind":"tail-left","page":2,"capacityMm":30,"maxBlankMm":0,"requiredEndIndex":1},
    {"kind":"tail-right","page":2,"capacityMm":30,"maxBlankMm":0}
  ]
}
```

- `blocks[].startIndex/endIndex`：连续、半开区间的**原文坐标**。根级范围等于首末块范围。不能漏段、重复段或把不可拆的公式截成两半。
- `advanceMm`：实际或已校验的占用增量，单位 mm；不是一律“行数×行距”。`compressMm/expandMm` 是当前规范允许且有证据的调整容量，默认 0。
- `continuationMm`：从该块开始续排时额外计入的高度，默认 0。调用方负责计入重复表头、续表标记及必要间距。
- `errorBelowMm/errorAboveMm`：占高相对名义值的非负误差范围，鲁棒检查必填。只有证据支持时才能填 0。
- `kind`：普通块用 `body`，通栏对象块用 `span`。`canBreakAfter` 表示该块之后是合法断点。完整段落移动、标题跟排、表格合并单元格及完整数据行约束必须在生成候选时落实；求解器不能从一个布尔值自行还原这些语义。
- `slots`：按阅读顺序排列。种类为 `column`、`span-left`、`span-right`、`span`、`tail-left`、`tail-right`。`page` 是数值或字符串标签。
- `capacityMm/maxBlankMm`：空间容量与允许的空白。通栏块的容量会减去同页上方双栏的较大占高；`belowSpan:true` 的下方栏还会扣除通栏块，不能重复扣减。
- `requiredStartIndex/requiredEndIndex`：**块数组的零起始边界位置**，不是原文坐标；结束值为不包含该块的边界。最终槽位必须覆盖全部块。
- `closePage:true` 将该槽位按页底留白约束检查。`observedOccupiedMm` 是已实测固定区间的占高，仅用于固定区间回放，不能用来给新断点指定想要的结果。

普通页、通栏截断处与末页的约束不同。末页两栏允许的实际底差上限为 0.1 mm。通栏上方优先齐底，不能靠让左栏明显更短通过。整表可放与不同合法续表断点应作为不同候选比较；没有固定的 6+2 比例。

### 输出

选择入口写 JSON：`status` 为 `one-offline-plan-selected` 或 `no-robust-offline-plan`，包含 `adobeCalls:0`、`selected` 以及每个候选的 `plan/review`、输入 SHA-256 和调整量。

名义窗口计划包含 `sourceIdentity` 和 `measurementSha256`，审核时必须与原测量完全匹配。其 `placements` 包含页、槽位种类、原文起止、`occupiedMm/blankMm/adjustmentMm`；失败时保留 `blockedAt/rejected/slotEvidence`。审核结果为 `robust-under-supplied-bounds` 或 `measurement-risk`，后者列出溢出、留白或齐底风险。

这些状态只针对提供的测量与误差范围。`ready-for-native-check` **不是已通过原生排版**。输出不是可直接运行的 InDesign 脚本。原生应用仍需来源绑定、保存重开、实际 PDF 检查及前篇保护验证。

当前算法先为每份输入选一个名义计划，再审核误差，并不穷尽所有鲁棒可行解。因此 `no-robust-offline-plan` 仅表示此次生成的名义计划没有通过，**不是无解证明**。例如占高10、允许压缩1、容量10、允许空白2、上偏差1 mm时，名义计划10会被拒绝，但9可能可行。将误差直接纳入搜索仍待开发；调用方不能凭此状态宣称已经尝试了所有合规排法。

## 首次试排测量数据与转换边界

真实首轮结果只放私有资料包，不在 Git。包内定位见其 README 和 manifest：

- `baseline.bodyFrames[]`：框页码、边界、栏数和逐行文本/原文位置/基线/字形尺寸/行距/段落范围。
- `baseline.formulas[]`：公式标签、实际几何框和页码；字体字号与来源绑定由相应公式清单提供。
- `baseline.tables[]`：表头数、列宽、行高、合并关系、单元格行测量与跨栏属性。
- `baseline.bands`、`baseline.issues`：栏带与首次检查问题；`bindings/articleStartIndex/preservedPageCount` 是本机复查上下文，不能照搬到别的文档。

原生测量 JSON **不能直接**传给选择入口；需要先按候选的段落、公式、表格断点生成上述 `blocks/slots`。本候选没有实现整个转换器，也没有实现所有公式的合法拆分。首页、有效栏顶、换栏首行与新连接关系必须独立测算；不确定时保留误差，不能复制答案的坐标后宣称独立预测。

`measured-advance.cjs` 导出 `pairSignature` 与 `reuseAdvance`，用于复用两条连续行的实测基线差。签名绑定宽度、内容、断点、排版标识和公式几何；改变任一项或变为新栏首就拒绝复用。调用方必须为 `compositionKey` 提供已验证的排版身份；它不能代替真实字符样式采集。返回 `null` 表示需重新测量/求解，不能默认为 0。

## 本机字形测量入口

`Test-JournalBodyPrediction.ps1` 需要 Windows PowerShell 7 + WPF 和本机合法安装的字体（宋体、汉仪中宋简、Times New Roman；导入数学模式还需 Cambria Math、Symbol）。字体仅来自私有云盘/本机，不随仓库提供。它与无需字体的云端数值求解器是两个阶段。

```powershell
pwsh -NoProfile -File experimental/offline-layout/Test-JournalBodyPrediction.ps1 -LogicalArticlePath logical.json -FormulaManifestPath formula-manifest.json -ReportPath prediction.json -MeasureSimpleRuns -MeasureItalicRuns -MeasureImporterMath -BalanceParagraph
```

逻辑稿输入为 `blocks:[{seq,role,text,runs}]`；源位置范围是半开字符区间，`runs` 可包含 `bold/italic/position`。行内公式用 `⟦EQ-001⟧` 标记。清单使用 `formulas.entries` 或根级 `entries`，含 `marker,widthMm,heightMm,basePointSize:10.5,inline`。缺失、重复或无效测量应拒绝，不能把标记字符串按普通文字估宽。可选 `-CompositeIdmlPath` 读取模板复合字体映射；不提供时使用估算映射，不能声称与模板完全一致。

`-Tracking` 只允许 −20 至 20，且非零必须同时指定 `-TrackingSequences`；它用于候选筛选，不自动把字距铺到全文。输出 `partial-planning-inputs` 的 `blocks` 中明确区分预测与未支持角色；名义行高不代表实际占高。公式宽于整栏时返回 `requires-formula-break-model`，不生成伪造的断行结果。WPF 不是 Adobe 段落书写器，断点可能不同。

## 验证

```powershell
pwsh -NoProfile -File tests/run_offline_candidate_regressions.ps1
pwsh -NoProfile -File tests/run_offline_candidate_regressions.ps1 -WithWindowsTypography
```

第一条只运行数值筛选和测量复用测试。第二条增加本机字形合成测试。所有测试均不打开 Adobe；未运行的原生验证不能被标为通过。


## 使用优先级（2026-11-12）

本模块按需选用，不是正式初排交付的必经环节。基础 Word/素材分析继续保留；专属字宽预测、误差校准和补测仅在选用本模块时运行。默认先做原生范围齐底，未解决的版面问题标注后交编辑。参见 [协作模式](../../docs/native-candidate-20261112.md)。
