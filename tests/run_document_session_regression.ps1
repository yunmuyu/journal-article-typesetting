param()
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $project '2-导入_InDesign\journal_document_session.jsxinc'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw 'Document session module is missing' }
$source = [IO.File]::ReadAllText($modulePath, [Text.Encoding]::UTF8)
$forbidden = @('app.activeDocument', 'selection', 'documents.close')
$found = @($forbidden | Where-Object { $source.IndexOf($_, [StringComparison]::Ordinal) -ge 0 })
if ($found.Count) { throw 'Document session uses implicit Adobe state: ' + ($found -join ', ') }
$modernSyntax = [regex]::Match($source, '(?m)(?:\b(?:let|const|class)\b|=>|\.\.\.)')
if ($modernSyntax.Success) { throw 'Document session is not ES3-compatible: ' + $modernSyntax.Value }
& node (Join-Path $PSScriptRoot 'test_journal_document_session.js')
if ($LASTEXITCODE -ne 0) { throw 'Document session behavior regression failed' }
'PASS explicit document session behavior without Adobe'
