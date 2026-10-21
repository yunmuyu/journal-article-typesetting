param()
$ErrorActionPreference='Stop'
$entry=Join-Path (Split-Path $PSScriptRoot) '2-导入_InDesign/Repair-JournalFormulaAssets.ps1'
$source=[IO.File]::ReadAllText($entry,[Text.Encoding]::UTF8)
$end=$source.IndexOf('$inputRoot=');if($end -lt 0){throw 'PYTHON_RESOLVER_BOUNDARY'}
$code=[ScriptBlock]::Create($source.Substring(0,$end)+'; $PythonExe')
$pythonOverrideBefore=$env:JOURNAL_PYTHON
try{
 $env:JOURNAL_PYTHON=$null
 $resolved=[string](& $code -InputDirectory fixture -OutputDirectory fixture)
 if(-not (Test-Path -LiteralPath $resolved -PathType Leaf) -or $resolved -match '\\Microsoft\\WindowsApps\\'){throw 'APP_ALIAS_SELECTED'}
 & $resolved -c "import sys; assert sys.version_info >= (3, 8)"
 if($LASTEXITCODE -ne 0){throw 'REAL_PYTHON_FAILED'}
 $explicit=[string](& $code -InputDirectory fixture -OutputDirectory fixture -PythonExe $resolved)
 if($explicit -ne $resolved){throw 'EXPLICIT_PYTHON_OVERRIDE_IGNORED'}
 'PASS real Python 3 resolution, App Execution Alias exclusion and explicit override'
}finally{$env:JOURNAL_PYTHON=$pythonOverrideBefore}
