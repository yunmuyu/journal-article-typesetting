# IdExtenso 的局部复用

- 项目：<https://github.com/indiscripts/IdExtenso>
- 固定提交：`0c2f70f4afa25aff691ebdc72575103965a66aee`
- 上游文件：[`core/Ext/$$.string.jsxinc`](https://github.com/indiscripts/IdExtenso/blob/0c2f70f4afa25aff691ebdc72575103965a66aee/core/Ext/%24%24.string.jsxinc#L116)
- 上游文件 SHA256：`fc7acf2e8b3c00be98a4888db652baf04c2b193577876f63ccde1d545f5878ef`
- 许可：MIT；保留在本目录 `LICENSE.txt`。

复用位置为 `2-导入_InDesign/journal_layout_rules.jsxinc` 的 `textCodePointAt`。
只改编 UTF-16 代理对解码算法；不加载框架，不改写 `String.prototype`，
不保留上游的 `callee.SIZE` 全局可见副作用，也不依赖 Adobe 文档或当前选区。
原上游函数保存在 `codePointAt.upstream.txt`，供离线审阅。

调用方 `orphanLine` 使用码点计数，补齐扩展汉字、兼容汉字及变体选择符的单字孤行判定；
继续忽略上标引文，保留原有常用字符的判定规则。
汉字区间和变体选择符范围依据 Unicode 17.0.0 `Blocks.txt`：
<https://www.unicode.org/Public/17.0.0/ucd/Blocks.txt>。
这里只判断字块范围，不声称识别该范围中每个码点是否已经分配或字体是否具有对应字形。

验证入口：`node --test tests/run_unicode_orphan_regression.cjs`。
测试直接调用现有共享入口 `JournalLayout.orphanLine`，而非只验证上游算法。

本次未采用：

- `$$.JSON`：上游明确输出扩展脚本表达式，不保证标准 JSON，不能替换供
  PowerShell `ConvertFrom-Json` 和 Node `JSON.parse` 消费的数据协议。
- `TextParcels`：适合可见文本位置索引，依赖 Dom、MultiStream 和框架环境；
  本次未验证其在现有复合字体、跨栏表格中的效果，不能宣称比当前测量更快或更准确。
