param(
    [Parameter(Mandatory=$true)][string]$ConfigPath,
    [ValidateSet('Apply','Check')][string]$Mode='Check',
    [switch]$ExportPreview
)
$ErrorActionPreference='Stop'
$configFile=(Get-Item -LiteralPath $ConfigPath).FullName
$config=Get-Content -LiteralPath $configFile -Raw -Encoding UTF8|ConvertFrom-Json
if(-not(Test-Path -LiteralPath $config.documentPath)){throw 'Document does not exist'}
if([IO.Path]::GetFileName($config.documentPath) -notmatch '(QA|copy|副本)'){throw 'Only test copies are allowed'}
$modulePath=Join-Path $PSScriptRoot 'journal_layout_rules.jsxinc'
$module=[IO.File]::ReadAllText($modulePath,[Text.Encoding]::UTF8)
$apply=if($Mode -eq 'Apply'){'true'}else{'false'}
$configJson=$config|ConvertTo-Json -Depth 20 -Compress
$preview=if($ExportPreview){'true'}else{'false'}
$script=$module+@"

try {
 var cfg=$configJson,d=app.open(File(cfg.documentPath));
 var result=JournalLayout.run(d,cfg,$apply);
 if($apply) d.save();
 if($preview){
  var folder=Folder(File(cfg.auditPath).parent.fsName+'/'+d.name.replace(/\.indd$/i,'')+'_预览');if(!folder.exists)folder.create();
  var prefs=app.jpegExportPreferences,old=prefs.properties;
  try{prefs.exportResolution=150;prefs.jpegQuality=JPEGOptionsQuality.HIGH;prefs.exportingSpread=false;prefs.jpegExportRange=ExportRangeOrAllPages.EXPORT_RANGE;
   for(var i=0;i<d.pages.length;i++){prefs.pageString=d.pages[i].name;d.exportFile(ExportFormat.JPG,File(folder.fsName+'/page-'+(i+1)+'.jpg'),false);}
  }finally{prefs.properties=old;}
 }
 if($apply)d.exportFile(ExportFormat.INDESIGN_MARKUP,File(cfg.documentPath.replace(/\.indd$/i,'.idml')),false);
 'AUDIT_WRITTEN';
}catch(e){'ERROR '+e+' LINE '+e.line;}
"@
$reportPath=[IO.Path]::ChangeExtension($config.auditPath,'.result.json')
[IO.File]::WriteAllText($reportPath,'{"passed":false,"stage":"running"}',[Text.UTF8Encoding]::new($false))
$app=New-Object -ComObject 'InDesign.Application.2020'
$result=$app.DoScript($script,1246973031)
if($result -ne 'AUDIT_WRITTEN'){[IO.File]::WriteAllText($reportPath,(@{passed=$false;stage='native';error=[string]$result}|ConvertTo-Json));throw $result}
[xml]$audit=Get-Content -LiteralPath $config.auditPath -Raw -Encoding UTF8
$errors=[Collections.Generic.List[string]]::new()
foreach($errorNode in $audit.SelectNodes('/audit/error')){$errors.Add($errorNode.code+': '+$errorNode.InnerText)}
function Normalize([string]$s){[regex]::Replace($s,'[\s\uFFFC\u0016]','')}
foreach($observation in $audit.SelectNodes('/audit/observation')){
 if($observation.InnerText -match '^CONTINUED_TABLE (\d+) '){
  if(@($config.reviewedContinuedTables) -notcontains [int]$Matches[1]){$errors.Add('CONTINUATION_REVIEW '+$Matches[1]+' verify repeated header and continuation label before accepting')}
 }
}
$source=Get-Content -LiteralPath $config.sourceParagraphs -Raw -Encoding UTF8|ConvertFrom-Json
$actual=@($audit.SelectNodes('/audit/story/p'))
$matched=0;$scriptChars=0
foreach($p in $source){
 $expected=Normalize $p.text
 if($expected.StartsWith('Absrtact:')){$expected='Abstract:'+$expected.Substring(9)}
 $found=@($actual|Where-Object{(Normalize $_.GetAttribute('text')) -ceq $expected})
 if($found.Count -ne 1){$errors.Add("CONTENT paragraph $($p.index) matches=$($found.Count)");continue}
 $matched++
 foreach($kind in @('superscripts','subscripts')){
  $sourceRuns=@($p.$kind)
  if(-not $sourceRuns.Count){continue}
  $position=if($kind -eq 'superscripts'){'1936749411'}else{'1935831907'}
  $expectedRuns=Normalize ($sourceRuns -join '')
  $actualRuns=Normalize (($found[0].r|Where-Object{[string]$_.position -eq $position}|ForEach-Object{$_.InnerText}) -join '')
  if($expectedRuns -cne $actualRuns){$errors.Add("SCRIPT_POSITION paragraph $($p.index) $kind expected=$expectedRuns actual=$actualRuns")}
  $scriptChars+=$expectedRuns.Length
 }
}
$rawTables=Get-Content -LiteralPath $config.sourceTables -Raw -Encoding UTF8|ConvertFrom-Json
$tables=if($rawTables.PSObject.Properties['tables']){@($rawTables.tables)}else{@($rawTables)}
$actualTables=@($audit.SelectNodes('/audit/table'));$cells=0
if($actualTables.Count -ne $tables.Count){$errors.Add('CONTENT table count')}
for($i=0;$i -lt $tables.Count;$i++){
 $rows=@($tables[$i].rows)
 if($i -ge $actualTables.Count){continue}
 if([int]$actualTables[$i].rows -ne $rows.Count){$errors.Add("CONTENT table $i rows")}
 for($r=0;$r -lt $rows.Count;$r++){
  for($c=0;$c -lt $rows[$r].Count;$c++){
   $nodes=@($actualTables[$i].SelectNodes('row'))
   if($r -ge $nodes.Count){$errors.Add("CONTENT table $i row $r missing");continue}
   $cellNodes=@($nodes[$r].SelectNodes('cell'))
   if($c -ge $cellNodes.Count -or (Normalize ([string]$rows[$r][$c])) -cne (Normalize $cellNodes[$c].GetAttribute('text'))){$errors.Add("CONTENT cell $i/$r/$c")}
   $cells++
  }
 }
}
foreach($asset in @($config.assets)){
 if(-not(Test-Path -LiteralPath $asset.path)){$errors.Add('ASSET_MISSING '+$asset.name);continue}
 if((Get-FileHash -LiteralPath $asset.path -Algorithm SHA256).Hash -cne $asset.sha256){$errors.Add('ASSET_CHANGED '+$asset.name)}
}
$summary=[ordered]@{document=$config.documentPath;mode=$Mode;passed=($errors.Count -eq 0);pages=[int]$audit.audit.pages;paragraphsMatched=$matched;paragraphsExpected=$source.Count;cellsCompared=$cells;scriptCharactersChecked=$scriptChars;errors=@($errors);moduleSHA256=(Get-FileHash -LiteralPath $modulePath -Algorithm SHA256).Hash}
$reportPath=[IO.Path]::ChangeExtension($config.auditPath,'.result.json')
[IO.File]::WriteAllText($reportPath,($summary|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
$summary|ConvertTo-Json -Depth 10
if($errors.Count){throw "Layout validation failed: $($errors.Count) errors. See $reportPath"}