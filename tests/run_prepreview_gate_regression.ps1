param()
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$gatePath = Join-Path $project '2-导入_InDesign\journal_prepreview_gate.jsxinc'
$entryPath = Join-Path $project '2-导入_InDesign\Invoke-JournalLayout.ps1'
$rulesPath = Join-Path $project '2-导入_InDesign\journal_layout_rules.jsxinc'

if (-not (Test-Path -LiteralPath $gatePath)) { throw 'Pre-preview gate module is missing' }
$gate = [IO.File]::ReadAllText($gatePath, [Text.Encoding]::UTF8)
$entry = [IO.File]::ReadAllText($entryPath, [Text.Encoding]::UTF8)
$rules = [IO.File]::ReadAllText($rulesPath, [Text.Encoding]::UTF8)
[void][scriptblock]::Create($entry)

$checks = [ordered]@{
    'body assembly resets direct overrides to 10.5/15' = $rules.Contains('p.pointSize=R.bodySize;p.leading=15;')
    'hard gate is called by shared audit' = $rules.Contains('JournalPrepreviewGate.audit')
    'invalid text metrics are blocking' = $gate.Contains("'TEXT_METRIC_INVALID'")
    'table-following style pollution is blocking' = $gate.Contains("'TABLE_STYLE_POLLUTION'")
    'table reservation defects are blocking' = $gate.Contains("'TABLE_RESERVATION'")
    'table host marker metrics are ignored' = $gate.Contains('hasContent = meaningful(range.contents)') -and -not $gate.Contains('meaningful(range.contents) || paragraph.tables.length')
    'overlap is blocking' = $gate.Contains("'GEOMETRY_OVERLAP'")
    'overlap page identity uses stable page identity' = $gate.Contains('pageKey:pageIdentity(page)') -and $gate.Contains('documentOffset') -and $gate.Contains('page.id')
    'trailing blank pages are blocking' = $gate.Contains("'TRAILING_BLANK_PAGE'")
    'large unexplained regions are blocking' = $gate.Contains("'LARGE_EMPTY_REGION'")
    'preview is disabled when native audit fails' = $entry.Contains("if(result.errors.length)previewScope='None';")
    'preview gate runs before JPEG export' = $entry.IndexOf("if(result.errors.length)previewScope='None';", [StringComparison]::Ordinal) -lt $entry.IndexOf("if(previewScope!=='None')", [StringComparison]::Ordinal)
}
$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value })
if ($failed.Count) { throw 'Pre-preview gate regression failed: ' + (($failed | ForEach-Object Key) -join '; ') }
& node (Join-Path $PSScriptRoot 'prepreview_gate_behavior_regression.js')
if ($LASTEXITCODE -ne 0) { throw 'Pre-preview gate behavior regression failed' }
'PASS numeric, geometry and preview-export hard gates are wired into the shared pipeline'
