param([Parameter(Mandatory=$true)][string]$InputDirectory,[Parameter(Mandatory=$true)][string]$OutputDirectory,[int[]]$Numbers=(1..10),[string]$PythonExe=$env:JOURNAL_PYTHON,[switch]$ExportPdf=$false,[switch]$ExportPng=$false)
$ErrorActionPreference='Stop'
if(-not $PythonExe){
 $candidates=@(Get-Command python.exe,python3.exe -CommandType Application -All -ErrorAction SilentlyContinue|Where-Object{$_.Source -notmatch '\\Microsoft\\WindowsApps\\' -and (Test-Path -LiteralPath $_.Source -PathType Leaf)})
 foreach($candidate in $candidates){
  $pythonVersion=& $candidate.Source -c "import sys; print(int(sys.version_info >= (3, 8)))" 2>$null
  if($LASTEXITCODE -eq 0 -and [string]$pythonVersion -eq '1'){$PythonExe=$candidate.Source;break}
 }
}
if(-not $PythonExe){throw 'PYTHON3_REQUIRED: set JOURNAL_PYTHON or pass -PythonExe with an installed Python 3 executable'}
$inputRoot=(Get-Item -LiteralPath $InputDirectory).FullName
$outputRoot=[IO.Path]::GetFullPath($OutputDirectory)
if($inputRoot -eq $outputRoot){throw 'Source and derivative folders must differ'}
$entry=(Join-Path $PSScriptRoot 'repair_formula_assets.jsx').Replace('\','/')
$app=New-Object -ComObject Illustrator.Application.CC.2019
$rows=[Collections.Generic.List[string]]::new()
$rows.Add("number`tsourceBasePt`toutputBasePt`tsongComparison`tcommaMoved`twidthPt`theightPt")
foreach($number in $Numbers){
 if($number -lt 1){throw 'Formula number must be positive'}
 $normalizedRoot=Join-Path $outputRoot '_wmf_import_inputs'
 [void][IO.Directory]::CreateDirectory($normalizedRoot)
 & $PythonExe (Join-Path $PSScriptRoot 'normalize_wmf_text_positions.py') (Join-Path $inputRoot ('formula-'+$number+'.wmf')) (Join-Path $normalizedRoot ('formula-'+$number+'.wmf')) | Out-Null
 if($LASTEXITCODE -ne 0){throw 'WMF_POSITION_NORMALIZATION_FAILED'}
 $job=@{inputDirectory=$normalizedRoot.Replace('\','/');outputDirectory=$outputRoot.Replace('\','/');number=$number;exportPdf=$ExportPdf.IsPresent;exportPng=$ExportPng.IsPresent}|ConvertTo-Json -Compress
 $entryJson=ConvertTo-Json -InputObject $entry -Compress
 $result=[string]$app.DoJavaScript('var JournalFormulaJob='+$job+';$.evalFile(File('+$entryJson+'));')
 if(-not $result.StartsWith([string]$number+"`t")){throw "Formula result invalid: $result"}
 $rows.Add($result)
}
[IO.File]::WriteAllText((Join-Path $outputRoot 'formula-font-audit.tsv'),($rows -join "`n"),[Text.UTF8Encoding]::new($false))
$rows