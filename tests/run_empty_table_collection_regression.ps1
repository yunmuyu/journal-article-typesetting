$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../2-导入_InDesign/Invoke-JournalLayout.ps1'),[Text.Encoding]::UTF8)
$assignment=($source -split "`r?`n"|Where-Object {$_.StartsWith('$tables=')})
if(@($assignment).Count -ne 1){throw 'TABLE_ASSIGNMENT_BOUNDARY'}
$cases=@(
 @{json='{"tables":[]}';count=0},
 @{json='{"tables":[{"rows":[]}]}';count=1},
 @{json='{"tables":[{"rows":[]},{"rows":[]}]}';count=2},
 @{json='[]';count=0},
 @{json='[{"rows":[]}]';count=1},
 @{json='[{"rows":[]},{"rows":[]}]';count=2}
)
foreach($case in $cases){
 $rawTables=ConvertFrom-Json -InputObject $case.json -NoEnumerate
 Invoke-Expression $assignment
 if($null -eq $tables -or $tables.Count -ne $case.count){throw "TABLE_COLLECTION_BOUNDARY $($case.json)"}
}
'PASS strict-mode zero, one and multiple source tables retain array shape'
