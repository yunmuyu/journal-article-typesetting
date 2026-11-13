# 开发候选增量：字体引用与 WMF 希腊字形

本轮仅更新开发候选，不合并正式分支。仓库只包含程序、合成测试和本说明；真实 Word、图件、字体、测量记录与本机配置不在提交范围。

## 已验证的修复

- 正文、表格和数字赋字体时，核对规范字体族、字形及回读名称；即使运行时声称已安装，残留 `Times New Roman (OTF)` 也不能通过。赋值仍无法清除已有文档旧引用时，明确失败，不宣称修复成功。
- 补入已有 IDML 修复器：仅在字体字形与 PostScript 名和已安装资源一一对应时替换字体引用，保留文本内容、斜体与其他字符属性，输出新 QA IDML，不覆盖输入。实稿中修复118处引用，重开缺字体数为0；这是人工组织的恢复路径，不是自动关闭/重开应用。
- 根据 WMF 字体字符集161识别希腊文本，使用源记录约束的占位符在 Illustrator 转曲前恢复 Unicode。核对字体、出现次数与字号，拒绝含糊匹配，不把合法的拉丁 Ó 全局替换为 Σ。实际24个公式素材中5个受影响，已生成正确Σ并在原生版面替换；基准仍为10.5 pt。
- `Build-JournalNativeFormulaManifest.ps1` 默认使用独立的 `formula-outline-v7-wmf-greek` 缓存身份，并把版本传入实际构建。旧缓存不改写；旧版本构建分支保留。居中省略号仍是显式v6分支，本轮未提升为v7默认行为。

## 本轮回归

候选工作树通过：source italic idempotence、review contract、composite digit、table native format、formula success/failure cleanup、formula cache contract、native formula contract、Python interpreter resolution、WMF launcher、WMF text positions、WMF charset，以及 PowerShell formula cache 和 IDML font repair 测试。Python发现测试需要已安装解释器在临时进程PATH中；不把本机路径提交到代码。

原生快速齐底继续复用已有 `alignFrameBodyLeading` / `leadingStep`，没有新写齐底算法。本次局部调用5.446秒，十栏通过且断点不变；未通过的首页左栏自动回退，只有作者简介的末页未处理。不是整篇耗时或全篇验收承诺。

## 保留限制

用户要求保存关闭后，未重开继续排版，也未在最后一轮字体/公式/齐底调整后重新导出全文PDF。因此不能把局部实测写成整篇出版终检通过。

本轮没有解决或重新验证之前记录的首页公式回排、第18页齐底、换栏高度预测误差、第二次整篇离线实排。离线求解仍是可选研究模块。IDML恢复可能带动既有页重排，必须核对前篇、绑定、文本及实际预览，不能以缺字体数为0代替版面验收。
