$ErrorActionPreference='Stop'
$source=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../2-导入_InDesign/Invoke-JournalLayout.ps1') -Raw -Encoding UTF8
$begin=$source.IndexOf('$actualTables=@(')
$end=$source.IndexOf('foreach($asset in @($config.assets))',$begin)
if($begin -lt 0 -or $end -lt 0){throw 'Audit content comparison block missing'}
$comparison=$source.Substring($begin,$end-$begin)
function Normalize([string]$Text){return ($Text -replace '\s','')}
function Test-SpanCase([int]$Expected,[int]$Actual,[bool]$Legacy=$false){
 $count=$Expected;$rows=[Collections.Generic.List[object]]::new();$merges=@();$xmlRows=@()
 for($index=0;$index -lt $count;$index++){
  $rows.Add([object[]]@($(if($index -eq 0){'group'}else{''}),"value$index"))
  if($index){
   $merge=[ordered]@{tableIndex=0;rowIndex=$index;cellIndex=0;intoRow=0;intoCell=0}
   if(-not $Legacy){$merge.expectedRowSpan=$Expected}
   $merges+=,[pscustomobject]$merge
   $xmlRows+="<row><cell text='value$index' rowSpan='1'/></row>"
  }else{$xmlRows+="<row><cell text='group' rowSpan='$Actual'/><cell text='value0' rowSpan='1'/></row>"}
 }
 $tables=@([pscustomobject]@{rows=$rows.ToArray()})
 $config=[pscustomobject]@{mergedEmptyCells=$merges}
 [xml]$audit="<audit><table rows='$count'>$($xmlRows -join '')</table></audit>"
 $errors=[Collections.Generic.List[string]]::new()
 Invoke-Expression $comparison
 if($Expected -eq $Actual -and $errors.Count){throw ($errors -join ';')}
 if($Expected -ne $Actual -and -not($errors -like 'CONTENT merge span*')){throw 'Incorrect rowSpan accepted'}
 if($cells -ne $count+1 -or $mergedEmptyCells -ne $count-1){throw 'Source cell comparison counts changed'}
}
Test-SpanCase 10 10
Test-SpanCase 5 5
Test-SpanCase 10 2
Test-SpanCase 2 2 $true
'PASS source table Check arbitrary spans and legacy two-row compatibility (no Adobe)'
