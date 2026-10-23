# Panel audit / WMF static regression repair — 2026-10-23

Base: `main` at `436ea07aa8f2a89ece06c7464dcf0fe4145da1c5`.
Isolated checkout: `D:\Codex-regression-panel-wmf-20261023`.
Branch: `fix/static-panel-wmf-regressions`.

## Reproduction and cause

- `node tests/run_panel_center_regression.cjs`: 4 passed, 8 failed with
  `TypeError: Cannot read properties of undefined (reading 'parentPage')`.
  The front story fixture had no text container. The full audit dereferences
  its first frame to locate the spacing guides before checking figure centers.
  Supplying that frame restores the existing figure assertions without weakening
  or bypassing any production audit checks. A new fixture test also checks that
  the unrelated `GUIDE_COUNT` diagnostic remains active.
- `node tests/run_wmf_text_positions_regression.cjs`: failed with status 9009
  and the Windows Store Python alias message on this host. The same wrapper
  passed with `JOURNAL_PYTHON=D:\Python313\python.exe`, confirming that the
  normalizer's position/header/idempotence/source-preservation assertions pass.
  The old wrapper also asserted on null status without including spawn errors,
  explaining why an absent interpreter could surface only as `null !== 0`.

Both failures were in the test harness. Production geometry and WMF code are
unchanged. No document application or production document was opened.

## Changes

The WMF wrapper honors an explicit `JOURNAL_PYTHON` executable path. Otherwise it
probes `py -3` first on Windows, then `python3` and `python`, requiring Python
3.8 or later. An unavailable interpreter gives `PYTHON3_REQUIRED` with launch
information and the override instruction. Once an interpreter is selected, a
real regression failure or launch failure fails immediately; it never retries
the test under another interpreter.

Eight synthetic launcher tests cover Windows and Unix selection, missing
commands, Store aliases, explicit paths containing spaces, invalid overrides,
all-candidate failure, real assertion failure, and signal termination.

## Validation

Environment: Windows, Node v24.16.0, Python 3.13. No dependency installation.

```powershell
$files = @(Get-ChildItem tests -Filter '*.cjs' | Sort-Object Name | ForEach-Object FullName)
node --test @files
# 75 files; 148 passed, 0 failed

node --test tests/bottom_interval_behavior_regression.js tests/prepreview_gate_behavior_regression.js tests/test_journal_document_session.js
# 3 files; 3 passed, 0 failed

D:\Python313\python.exe -m unittest discover -s tests -p 'test_*.py'
# 44 tests; OK; WMF position script also passed

git diff --check
# passed
```

The two repaired entry points were also run directly without an interpreter
override: panel audit 13/13, WMF position assertions passed. Existing 2x3 and 1x2
left/right center checks, second-row offset detection and wrong-page detection
remain enabled.

Only static Node/Python tests and synthetic data were used. The full
`run_all_regressions.ps1` entry was not run because its later stage creates an
InDesign COM object. This result does not constitute live InDesign layout QA.
PR #1's branch was not modified.
