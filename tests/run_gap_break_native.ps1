#Requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Path $EvidenceDirectory -Force|Out-Null
$root=Split-Path $PSScriptRoot -Parent
$code=''
foreach($name in @('journal_regression_snapshot.jsxinc','journal_layout_measurement.jsxinc','journal_gap_solver.jsxinc','journal_gap_layout.jsxinc','journal_layout_rules.jsxinc')){$code+=[IO.File]::ReadAllText((Join-Path $root ('2-导入_InDesign/'+$name)),[Text.Encoding]::UTF8)+[Environment]::NewLine}
$code+='var NativeGapEvidenceDirectory='+($EvidenceDirectory|ConvertTo-Json -Compress)+';'+[Environment]::NewLine
$code+=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'gap_break_native.jsx'),[Text.Encoding]::UTF8)
[IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'executed.jsx'),$code,[Text.Encoding]::UTF8)
$app=New-Object -ComObject InDesign.Application.2020
$result=$app.DoScript($code,1246973031)|ConvertFrom-Json
if(!$result.passed){throw ($result|ConvertTo-Json -Depth 10)}
$result|ConvertTo-Json -Depth 10
