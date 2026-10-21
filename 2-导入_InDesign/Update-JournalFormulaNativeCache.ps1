param(
    [Parameter(Mandatory=$true)][int]$DocumentId,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [Parameter(Mandatory=$true)][string]$ManifestPath,
    [Parameter(Mandatory=$true)][string]$ReportPath,
    [Parameter(Mandatory=$true)][string]$BackupPath,
    [Parameter(Mandatory=$true)][string]$QueueDirectory,
    [Parameter(Mandatory=$true)][string]$TaskId,
    [Parameter(Mandatory=$true)][string]$LeaseId
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'JournalInDesignScript.psm1') -Force
$lease=Get-Content -LiteralPath (Join-Path $QueueDirectory 'locks/indesign.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($lease.taskId -cne $TaskId -or $lease.leaseId -cne $LeaseId){throw 'FORMULA_UPDATE_LEASE_MISMATCH'}
if([IO.Path]::GetFileName($OutputPath) -notmatch '(?i)QA|copy|副本' -or [IO.Path]::GetFileName($BackupPath) -notmatch '(?i)QA|copy|副本'){throw 'FORMULA_UPDATE_QA_REQUIRED'}
if([IO.Path]::GetFullPath($OutputPath) -ieq [IO.Path]::GetFullPath($BackupPath)){throw 'FORMULA_UPDATE_BACKUP_COLLISION'}
$manifest=Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8|ConvertFrom-Json
if($manifest.mode -ne 'native-idms' -or @($manifest.entries).Count -ne $manifest.formula_count){throw 'FORMULA_UPDATE_MANIFEST'}
$numbers=@{}
foreach($entry in $manifest.entries){
    if($numbers.ContainsKey([int]$entry.number)){throw 'FORMULA_UPDATE_DUPLICATE_NUMBER'}
    $numbers[[int]$entry.number]=$true
    if((Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash -ine $entry.sha256){throw "FORMULA_UPDATE_SHA $($entry.number)"}
    if($entry.basePointSize -ne 10.5 -or -not $entry.cacheKey -or -not $entry.sourceSha256 -or -not $entry.ruleVersion){throw "FORMULA_UPDATE_PROVENANCE $($entry.number)"}
}
$spec=@{documentId=$DocumentId;path=[IO.Path]::GetFullPath($OutputPath);backup=[IO.Path]::GetFullPath($BackupPath);manifest=$manifest}|ConvertTo-Json -Depth 90 -Compress
[IO.File]::WriteAllText($ReportPath+'.input.json',$spec,[Text.UTF8Encoding]::new($false))
$code=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_regression_snapshot.jsxinc'))+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_layout_rules.jsxinc'))+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_article_assembly.jsxinc'))+"var FormulaUpdateSpec=$spec;`n"+@'
(function(s){var ui=app.scriptPreferences.userInteractionLevel,redraw=app.scriptPreferences.enableRedraw;try{
app.scriptPreferences.userInteractionLevel=UserInteractionLevels.NEVER_INTERACT;app.scriptPreferences.enableRedraw=false;
function progress(value){var f=File(s.backup+'.progress.json');f.encoding='UTF-8';if(!f.open('w'))throw Error('PROGRESS_WRITE');f.write(JournalRegressionSnapshot.json(value));f.close();}
var d=app.documents.itemByID(s.documentId);if(!d.isValid||d.fullName.fsName!==File(s.path).fsName)throw Error('DOC_ID_PATH');
var backup=File(s.backup);if(!backup.exists)d.saveACopy(backup);
var changed=[],kept=[],numbers=[];
for(var i=0;i<s.manifest.entries.length;i++){
    var entry=s.manifest.entries[i],contract={formulaCacheContract:[entry]};
    if(JournalLayout.formulaCacheIssues(d,contract).length){
        progress({phase:'replacing',number:entry.number,completed:changed,kept:kept});
        var group=JournalArticleAssembly.replaceNativeFormula(d,entry.number,s.manifest);
        group.insertLabel('formula-display',entry.inline?'false':entry.displayNumber===null?'unnumbered':'true');
        group.insertLabel('formula-printed-number',entry.displayNumber===null?'':String(entry.displayNumber));changed.push(entry.number);
    }else kept.push(entry.number);
    numbers.push({number:entry.number,inline:entry.inline,displayNumber:entry.displayNumber});
}
progress({phase:'restore-source-numbering',numbers:numbers,completed:changed,kept:kept});
var numberErrors=JournalLayout.sourceFormulaNumbering(d,{formulaNumbers:numbers},true);if(numberErrors.length)throw Error(numberErrors.join(';'));
d.recompose();JournalLayout.formulaLineSpacing(d,true);JournalLayout.fitFormulaNumbers(d);
var errors=JournalLayout.formulaCacheIssues(d,{formulaCacheContract:s.manifest.entries}).concat(JournalLayout.sourceFormulaNumbering(d,{formulaNumbers:numbers},false));
for(var oi=0;oi<d.allPageItems.length;oi++){var item=d.allPageItems[oi];if(!/^source-formula-/.test(item.label))continue;if(item.constructor.name!=='Group'||item.allGraphics.length||item.extractLabel('formula-native-paste')!=='true'||Number(item.extractLabel('formula-base-point-size'))!==10.5||Math.abs(item.absoluteHorizontalScale-100)>.01||Math.abs(item.absoluteVerticalScale-100)>.01)errors.push('FORMULA_NATIVE_ACTUAL '+item.label);}
if(errors.length)throw Error(errors.join(';'));d.save();
return JournalRegressionSnapshot.json({status:'latest-formulas-integrated-layout-unchecked',documentId:d.id,outputPath:d.fullName.fsName,pages:d.pages.length,replaced:changed,alreadyCurrent:kept,formulaCount:s.manifest.entries.length,provenanceErrors:errors});
}catch(e){return JournalRegressionSnapshot.json({status:'failed',failure:String(e),line:e.line});}finally{app.scriptPreferences.userInteractionLevel=ui;app.scriptPreferences.enableRedraw=redraw;}})(FormulaUpdateSpec);
'@
$app=New-Object -ComObject InDesign.Application.2020
$raw=[string](Invoke-JournalInDesignScript -Application $app -Code $code)
[IO.File]::WriteAllText($ReportPath,$raw,[Text.UTF8Encoding]::new($false))
$result=$raw|ConvertFrom-Json
if($result.status -eq 'failed'){throw $result.failure}
$result|ConvertTo-Json -Depth 20
