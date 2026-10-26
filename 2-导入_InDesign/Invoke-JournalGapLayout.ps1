#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourcePath,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$ReportPath,
    [string]$ConfigPath,
    [ValidateSet('Measure','Solve')][string]$Mode='Solve'
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'JournalInDesignScript.psm1') -Force
$source=(Get-Item -LiteralPath $SourcePath).FullName
$output=[IO.Path]::GetFullPath($OutputPath)
$report=[IO.Path]::GetFullPath($ReportPath)
if([IO.Path]::GetExtension($source) -ine '.indd'){throw 'GAP_SOURCE_INDD_REQUIRED'}
if([IO.Path]::GetExtension($output) -ine '.indd' -or [IO.Path]::GetFileNameWithoutExtension($output) -notmatch '(?i)QA|copy|副本'){throw 'GAP_OUTPUT_QA_REQUIRED'}
if($source -ieq $output -or $source -ieq $report -or $output -ieq $report){throw 'GAP_PATHS_MUST_DIFFER'}
if([IO.Path]::GetExtension($report) -ine '.json'){throw 'GAP_REPORT_JSON_REQUIRED'}
if((Test-Path -LiteralPath $output) -or (Test-Path -LiteralPath $report)){throw 'GAP_OUTPUT_ALREADY_EXISTS'}
$config=@{}
if($ConfigPath){$config=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8|ConvertFrom-Json -AsHashtable}
$job=@{source=$source;output=$output;mode=$Mode;config=$config}|ConvertTo-Json -Depth 50 -Compress
$code=''
foreach($file in @('journal_document_session.jsxinc','journal_regression_snapshot.jsxinc','journal_layout_measurement.jsxinc','journal_gap_solver.jsxinc','journal_gap_layout.jsxinc')){
    $code+=[IO.File]::ReadAllText((Join-Path $PSScriptRoot $file),[Text.Encoding]::UTF8)+"`n"
}
$code+="var GapJob=$job;"+@'
(function(job){
 var session=null,d=null,result=null,ui=app.scriptPreferences.userInteractionLevel,redraw=app.scriptPreferences.enableRedraw,sourceUnsaved=false;
 try{
  for(var i=0;i<app.documents.length;i++){var doc=app.documents[i];if(doc.saved&&JournalDocumentSession.normalizePath(doc.fullName)===JournalDocumentSession.normalizePath(job.source)&&doc.modified)sourceUnsaved=true;}
  session=JournalDocumentSession.acquire(app,job.output);
  if(!session.openedHere)throw Error('GAP_TARGET_ALREADY_OPEN');d=session.document;
  app.scriptPreferences.userInteractionLevel=UserInteractionLevels.NEVER_INTERACT;app.scriptPreferences.enableRedraw=false;
  d.viewPreferences.horizontalMeasurementUnits=MeasurementUnits.MILLIMETERS;d.viewPreferences.verticalMeasurementUnits=MeasurementUnits.MILLIMETERS;
  d.viewPreferences.rulerOrigin=RulerOrigin.PAGE_ORIGIN;d.zeroPoint=[0,0];d.recompose();
  if(job.mode==='Measure')result={status:'measured',measurement:JournalGapLayout.measure(d,job.config),fullArticleAcceptance:false};
  else result=JournalGapLayout.solve(d,job.config);
  result.documentId=d.id;result.output=String(d.fullName.fsName);result.pages=d.pages.length;result.sourceSnapshot='saved-file';result.sourceHasUnsavedChanges=sourceUnsaved;
  if(job.config.articlePageRange)result.articlePageRange=[job.config.articlePageRange[0],Math.min(job.config.articlePageRange[1],d.pages.length-1)];
  else result.articlePageRange=[0,d.pages.length-1];
  if(job.mode==='Solve'&&result.appliedDecisions>0)d.save();
 }catch(e){result={status:'failed',error:String(e),line:e.line,fullArticleAcceptance:false};}
 finally{
  if(session&&session.openedHere){try{JournalDocumentSession.close(d||session.document,session,SaveOptions.NO);}catch(e){result={status:'failed',error:'GAP_CLOSE '+String(e),fullArticleAcceptance:false};}}
  app.scriptPreferences.userInteractionLevel=ui;app.scriptPreferences.enableRedraw=redraw;
 }
 return JournalRegressionSnapshot.json(result);
})(GapJob);
'@
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $output))
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $report))
$before=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
Copy-Item -LiteralPath $source -Destination $output
$priorEngine=$env:JOURNAL_SCRIPT_ENGINE
try{
    $env:JOURNAL_SCRIPT_ENGINE='journal-gap-solver-v1'
    $app=New-Object -ComObject InDesign.Application.2020
    $native=[string](Invoke-JournalInDesignScript -Application $app -Code $code)
    if([string]::IsNullOrWhiteSpace($native)){throw 'GAP_NATIVE_RESULT_EMPTY'}
    $result=$native|ConvertFrom-Json -AsHashtable
    $result.source=$source
    $result.sourceSha256=$before
    $result.sourceFileUnchanged=((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -eq $before)
    $result.outputSha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
    [IO.File]::WriteAllText($report,($result|ConvertTo-Json -Depth 50),[Text.UTF8Encoding]::new($false))
    if(-not $result.sourceFileUnchanged){throw 'GAP_SOURCE_CHANGED_DURING_RUN'}
    if($result.status -eq 'failed'){throw ('GAP_NATIVE_FAILED '+$result.error)}
    $remainingCount=$null
    if($Mode -eq 'Solve'){$remainingCount=@($result.remaining).Count}
    @{status=$result.status;output=$output;report=$report;elapsedMs=$result.elapsedMs;trialCount=$result.trialCount;appliedDecisions=$result.appliedDecisions;remaining=$remainingCount;sourceHasUnsavedChanges=$result.sourceHasUnsavedChanges}|ConvertTo-Json
    if($Mode -eq 'Solve' -and $result.status -eq 'blocked-large-gaps'){throw "GAP_UNRESOLVED report=$report"}
}catch{
    if(-not(Test-Path -LiteralPath $report)){[IO.File]::WriteAllText($report,(@{status='failed';error=[string]$_;fullArticleAcceptance=$false}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))}
    throw
}finally{$env:JOURNAL_SCRIPT_ENGINE=$priorEngine}
