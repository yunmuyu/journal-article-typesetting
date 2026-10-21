# 期刊文章自动排版与检查系统

这是从人工排版示范学习、经赵志威和张芳芳两篇验证的独立项目。第一版基线为 **v1.0.0**；当前工作分支包含后续工具修订。

私有仓库：https://github.com/yunmuyu/journal-article-typesetting

本项目负责文章排版规范化、版面和内容检查、恢复副本及回归验证。原有[word-to-indesign-toolkit](https://github.com/yunmuyu/word-to-indesign-toolkit)是独立的Word提取/导入工具，本项目复用其提取组件，不属于旧工具项目的后续版本。

## 当前工具修订

最新说明见 [2026-10-21工具更新](docs/releases/2026-10-21-tools-update.md)。`run_journal_article.py` 仍是未完成原型，正式流程使用下面的分阶段组件。表内公式及原位装配等限制以更新说明为准。

## 运行流程

1. 使用1-提取_Word转JSON组件提取Word数据；保留原稿只读。
2. 在测试INDD副本中完成图表装配和故事绑定，准备本篇Word核对输入及配置。
3. 运行Invoke-JournalLayout.ps1 -ConfigPath "文章配置.json" -Mode Apply -ExportPreview。
4. 运行同一入口的Check，核对原文、实际字体、间距、底线和图表位置；查看页面预览，再交用户审看。

本版本还不能从任意Word直接全自动成稿，续表框自动定位和复杂公式通用自动转轮廓仍未完成。任何技术检查失败不得当作合格稿交付。

## 安装与入口

在2-导入_InDesign目录运行deploy_to_indesign.ps1 -NoPause。脚本会安装到InDesign脚本面板的 **期刊文章自动排版系统** 子目录，并备份、核对SHA256；不会覆盖旧Word导入工具的根目录入口。

- import_word_article_to_indesign.jsx和0文章.jsx：本系统的文章导入适配器。
- journal_layout_rules.jsxinc：共享排版与检查规则。
- journal_layout_and_check.jsx：脚本面板版面处理入口。
- Invoke-JournalLayout.ps1：包括Word内容对照的完整检查入口。

## 标准和验证

- [排版执行标准](docs/期刊文章排版执行标准.md)
- [程序运行说明](docs/期刊排版程序运行说明.md)
- [组件来源与项目边界](docs/组件来源与项目边界.md)
- [第一版验证范围](docs/releases/v1.0.0.md)
- [版本记录](CHANGELOG.md)

第一版两篇通过61/80段、35/150单元格及41/53上下标字符检查，12类错误注入被拦截，重复运行版面不漂移。默认双页左页起排。源码、规则、测试和验证摘要纳入Git；实稿、图源、INDD、IDML及本机配置保留本地。

后续新文章在本项目新建测试副本并迭代提交，不移动v1.0.0标签，也不将新系统功能提交到旧Word工具库。