param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$outputRoot=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$root=Join-Path $PSScriptRoot '..\2-导入_InDesign'
Import-Module (Join-Path $root 'JournalInDesignScript.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'NativeRegressionReport.psm1') -Force
$env:JOURNAL_SCRIPT_ENGINE='journal-continuation-synthetic-regression'
$prefix=[IO.File]::ReadAllText((Join-Path $root 'journal_regression_snapshot.jsxinc'))+"`n"+[IO.File]::ReadAllText((Join-Path $root 'journal_layout_rules.jsxinc'))
$runId=[guid]::NewGuid().ToString('N');$startedUtc=[DateTime]::UtcNow
$reportPath=Join-Path $outputRoot ('native-continuation-'+$runId+'.json')
$reportJson=ConvertTo-Json $reportPath -Compress
$runIdJson=ConvertTo-Json $runId -Compress;$startedJson=ConvertTo-Json ($startedUtc.ToString('o')) -Compress
$code=@"
(function(){var d=null,r={passed:false,saved:false,run_id:$runIdJson,started_utc:$startedJson,source_sha256:'__SCRIPT_SHA256__'},oldUnit=app.scriptPreferences.measurementUnit,oldUI=app.scriptPreferences.userInteractionLevel;
function check(ok,message){if(!ok)throw Error(message);}
try{
app.scriptPreferences.measurementUnit=MeasurementUnits.MILLIMETERS;app.scriptPreferences.userInteractionLevel=UserInteractionLevels.NEVER_INTERACT;
d=app.documents.add(false);r.documentId=d.id;
var page=d.pages[0],first=page.textFrames.add({geometricBounds:[20,20,48,80]}),next=page.textFrames.add({geometricBounds:[20,90,120,150]});
next.previousTextFrame=first;first.contents='\r';var story=first.parentStory;story.insertLabel('journal-role','body');
var table=story.insertionPoints[0].tables.add({bodyRowCount:7,columnCount:1});table.label='source-table-1';table.columns[0].width=55;
for(var i=0;i<7;i++){table.rows[i].cells[0].contents='synthetic row '+i;table.rows[i].minimumHeight=6;table.rows[i].autoGrow=true;}
var template=page.textFrames.add({geometricBounds:[5,20,20,80]});template.contents='（续表）';template.paragraphs[0].pointSize=9;template.paragraphs[0].leading=12;
r.templateBefore={contents:String(template.contents),story:String(template.parentStory.contents)};
d.recompose();r.fragmentsBefore=JournalLayout.continuedTableFragments(d).length;
r.template={contents:String(template.contents),story:String(template.parentStory.contents),pointSize:Number(template.paragraphs[0].pointSize),leading:Number(template.paragraphs[0].leading),textFrames:d.textFrames.length};
check(r.fragmentsBefore===1,'synthetic table must continue in second frame');
var result=JournalLayout.syncContinuedTables(d,d);r.created=result.markers;
check(result.markers===1,'cross-frame table needs a marker');
var key='journal-continued-source-table-1-'+next.id,marker=null;
for(i=0;i<d.allPageItems.length;i++)if(d.allPageItems[i].label===key)marker=d.allPageItems[i];
check(marker&&marker.nonprinting===false,'valid marker must print');
var markerId=marker.id;JournalLayout.syncContinuedTables(d,d);
check(d.pageItems.itemByID(markerId).isValid,'repeat sync must retain the same marker');
marker.nonprinting=true;
check(JournalLayout.continuedTableIssues(d).length>0,'hidden marker must fail Check');
JournalLayout.syncContinuedTables(d,d);check(marker.nonprinting===false,'sync must restore printable status');
var bounds=first.geometricBounds;bounds[2]=110;first.geometricBounds=bounds;d.recompose();
r.fragmentsAfter=JournalLayout.continuedTableFragments(d).length;
check(r.fragmentsAfter===0,'table must fit first frame after growth');
result=JournalLayout.syncContinuedTables(d,d);
check(result.removedMarkers===1&&result.restoredFrames===1,'obsolete marker and reserved top must be released');
check(!d.pageItems.itemByID(markerId).isValid,'obsolete marker must be removed');
check(Math.abs(Number(next.geometricBounds[0])-20)<.001,'second frame top must be restored');
check(JournalLayout.continuedTableIssues(d).length===0,'final continuation gate must pass');
r.passed=true;r.removed=result.removedMarkers;r.restored=result.restoredFrames;
}catch(e){r.error=String(e);r.line=e.line;}finally{try{if(d)d.close(SaveOptions.NO);}catch(closeError){r.closeError=String(closeError);r.passed=false;}try{app.scriptPreferences.measurementUnit=oldUnit;app.scriptPreferences.userInteractionLevel=oldUI;}catch(restoreError){r.restoreError=String(restoreError);r.passed=false;}var f=File($reportJson);f.encoding='UTF-8';f.open('w');f.write(JournalRegressionSnapshot.json(r));f.close();}
return r.run_id;}());
"@
$hash=[Security.Cryptography.SHA256]::Create();$sourceSha=[BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($prefix+"`n"+$code))).Replace('-','').ToLowerInvariant()
$code=$code.Replace('__SCRIPT_SHA256__',$sourceSha)
$app=New-Object -ComObject InDesign.Application.2020
$scriptResult=Invoke-JournalInDesignScript -Application $app -Code ($prefix+"`n"+$code)
$result=Assert-NativeRegressionReport -Path $reportPath -RunId $runId -StartedUtc $startedUtc -SourceSha256 $sourceSha -ScriptResult ([string]$scriptResult)
$result | ConvertTo-Json -Compress
