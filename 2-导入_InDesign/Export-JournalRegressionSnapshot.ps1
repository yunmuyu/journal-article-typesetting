param([Parameter(Mandatory=$true)][string]$ConfigPath)
Import-Module (Join-Path $PSScriptRoot 'JournalInDesignScript.psm1') -Force
$ErrorActionPreference='Stop'
$spec=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$config=$spec | ConvertTo-Json -Depth 30 -Compress
$module=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_regression_snapshot.jsxinc'),[Text.Encoding]::UTF8)
$session=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_document_session.jsxinc'),[Text.Encoding]::UTF8)
foreach($entry in @($spec.baseline,$spec.candidate)){
    if(-not(Test-Path -LiteralPath $entry.documentPath)){throw "DOCUMENT_MISSING $($entry.documentPath)"}
    if($entry.PSObject.Properties['sha256'] -and $entry.sha256){
        if((Get-FileHash -LiteralPath $entry.documentPath -Algorithm SHA256).Hash -ne $entry.sha256){throw 'BASELINE_HASH_CHANGED'}
    }
}
$script=$module+"`n"+$session+@"
var __regressionResult;
try{__regressionResult=(function(){
var spec=$config,out={},old=app.scriptPreferences.userInteractionLevel;
try{
app.scriptPreferences.userInteractionLevel=UserInteractionLevels.NEVER_INTERACT;
var names=['baseline','candidate'];
for(var i=0;i<names.length;i++){
 var name=names[i],entry=spec[name];
 out[name]=JournalDocumentSession.withReadOnlyDocument(app,entry.documentPath,function(d){
  if(entry.documentId&&d.id!==entry.documentId)throw Error('DOCUMENT_ID_CHANGED '+name);
  if(name==='baseline'&&d.modified)throw Error('BASELINE_UNSAVED_CHANGES');
  return JournalRegressionSnapshot.capture(d,entry);
 },SaveOptions.NO);
}
var file=File(spec.outputPath);file.encoding='UTF-8';if(!file.open('w'))throw Error('SNAPSHOT_WRITE');
file.write(JournalRegressionSnapshot.json(out));file.close();
return 'REGRESSION_SNAPSHOT_OK';
}finally{app.scriptPreferences.userInteractionLevel=old;}
}());}catch(e){__regressionResult='ERROR '+e+' LINE '+e.line;}
__regressionResult;
"@
$process=Get-Process InDesign -ErrorAction Stop | Select-Object -First 1
if(-not $process.Responding -or $process.MainWindowTitle -match '^(Script Alert|脚本警告|警告)'){throw 'INDESIGN_BLOCKED'}
$app=New-Object -ComObject 'InDesign.Application.2020'
$answer=[string](Invoke-JournalInDesignScript -Application $app -Code ($script))
if($answer -ne 'REGRESSION_SNAPSHOT_OK'){throw $answer}
$answer
