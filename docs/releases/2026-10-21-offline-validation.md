# 2026-10-21 上传前离线验证

在本次Git工作副本运行，15组全部通过；未启动Adobe或Word。安装测试仅使用临时模拟目录，编排测试写入被Git忽略的临时目录。

| 测试 | 结果 |
|---|---|
| `run_native_idms_assembly_regression.cjs` | PASS |
| `run_formula_cache_contract_regression.cjs` | PASS |
| `run_formula_alignment_regression.cjs` | PASS |
| `run_assembly_page_growth_regression.cjs` | PASS |
| `run_preview_pdf_range_regression.cjs` | PASS |
| `test_journal_document_session.js` | PASS |
| `run_session_lifecycle_regression.cjs` | PASS |
| `run_integrated_article_contract_regression.cjs` | PASS |
| `run_review_contract_regression.cjs` | PASS |
| `test_extraction.py` | PASS |
| `test_extract_journal_article.py` | PASS |
| `test_prepare_article_job.py` | PASS |
| `test_wmf_charset_regression.py` | PASS |
| `run_journal_pipeline_regression.ps1` | PASS |
| `run_formula_cache_regression.ps1` | PASS |

Node测试使用Node.js；Python测试使用Python 3.13的 `-B -X utf8`；PowerShell测试使用pwsh -NoProfile。
真实Adobe公式素材的实际验证范围见同目录更新说明；未据此宣称完整文章生产验收。
