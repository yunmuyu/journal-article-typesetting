# 简式公式转换（开发候选）

入口：`mathtype_to_word_text.py`，Python 3.11+。本目录收录用户维护的 `mathtype-simple-word-text` 工具运行源码及本轮修复，避免只提交一个无法独立运行的补丁；不包含虚拟环境、安装包、实稿或本机路径。依赖沿用该工具已验证版本，见 `requirements.txt`。

```sh
python -m pip install -r tools/simple-formula/requirements.txt
python tools/simple-formula/mathtype_to_word_text.py input.docx --output converted.docx --report report.json
python tools/simple-formula/test_math_text.py
```

输入用原稿，输出和报告使用新路径。转换报告包含转换/保留数量与字体槽位规范化数量。短且可识别的 MathType/OMML 转为文本；复杂结构仍保留原对象。新生成数学文本的语义规则与已有普通文本分开处理。

本轮修复：已有文本只在 Times New Roman、`hint=eastAsia`、短上下标或数学符号条件同时符合时调整字体槽位；保留源 `w:i`、`w:b`、`w:vertAlign`、`w:position`。不再将普通正文中的单个字母推断为数学变量，因此不会把 `[J]` 改斜体，也不会把原有 `ij` 斜体下标改正体。

验证：合成字符格式测试、临时合成 DOCX 的完整 CLI 转换，以及本机原稿临时副本复跑。原稿复跑的 MathType 转换5/保留24、OMML转换1；3处ij斜体下标保留，文献J无误加斜体。实稿不入库。

`.doc` 的既有 Word/LibreOffice 转换适配器随依赖闭包收录，本轮未重测；本轮验证范围为 DOCX。工具不是 Adobe 排版或齐底入口，不会替代独立版面检查。
