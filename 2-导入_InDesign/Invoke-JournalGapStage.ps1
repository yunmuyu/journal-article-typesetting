#Requires -Version 7.0
[CmdletBinding()]
param(
 [Parameter(Mandatory)][string]$ConfigPath,
 [Parameter(Mandatory)][int]$DocumentId,
 [Parameter(Mandatory)][string]$ReportPath,
 [ValidateSet('BeforeBottom','AfterBottom')][string]$Phase='BeforeBottom',
 [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'JournalInDesignScript.psm1') -Force
$c=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8|ConvertFrom-Json
if([IO.Path]::GetFileName($c.documentPath) -notmatch '(?i)QA|copy|副本'){throw 'GAP_STAGE_QA_REQUIRED'}
if(@($c.bindings|Where-Object role -eq 'body').Count -ne 1){throw 'GAP_STAGE_BODY_BINDING_REQUIRED'}
if(Test-Path -LiteralPath $ReportPath){throw 'GAP_STAGE_REPORT_EXISTS'}
$bodyId=[int](@($c.bindings|Where-Object role -eq 'body')[0].id)
$spec=@{id=$DocumentId;bodyId=$bodyId;path=$c.documentPath;config=$c;phase=$Phase}|ConvertTo-Json -Depth 80 -Compress
$code=''
foreach($file in @('journal_regression_snapshot.jsxinc','journal_layout_measurement.jsxinc','journal_gap_solver.jsxinc','journal_gap_layout.jsxinc','journal_layout_rules.jsxinc')){$code+=[IO.File]::ReadAllText((Join-Path $PSScriptRoot $file))+[Environment]::NewLine}
$code+='var GapStageJob='+$spec+';'+@'
(function(s){
 var ui=app.scriptPreferences.userInteractionLevel,redraw=app.scriptPreferences.enableRedraw;
 try{
  var d=app.documents.itemByID(s.id);if(!d.isValid||String(d.fullName.fsName).toLowerCase()!==String(File(s.path).fsName).toLowerCase())throw Error('GAP_STAGE_DOCUMENT_IDENTITY');
  app.scriptPreferences.userInteractionLevel=UserInteractionLevels.NEVER_INTERACT;app.scriptPreferences.enableRedraw=false;
  var body=d.stories.itemByID(s.bodyId);
  var result;
  if(s.phase==='BeforeBottom')result=JournalGapLayout.solve(d,s.config);
  else{
   var frames=body.textContainers,items=[],all=d.allPageItems,range=s.config.articlePageRange||[0,d.pages.length-1];
   for(var i=0;i<all.length;i++)if(all[i].parentPage&&all[i].parentPage.documentOffset>=range[0]&&all[i].parentPage.documentOffset<=range[1])items.push(all[i]);
   var view={stories:[body],textFrames:frames,allPageItems:items,recompose:function(){d.recompose();}};
   var fragments=JournalLayout.continuedTableFragments(view),continuations={markers:0};
   if(fragments.length)continuations=JournalLayout.syncContinuedTables(view,d);
   var measured=JournalGapLayout.measure(d,s.config),limits=JournalGapSolver.options(s.config.gapSolver),remaining=[];
   remaining=JournalGapSolver.unresolved(measured,limits);
   result={status:remaining.length||measured.hardErrors.length?'blocked-large-gaps':'gap-check-passed',remaining:remaining,hardErrors:measured.hardErrors,continuations:continuations,fullArticleAcceptance:false};
  }
  d.save();result.documentId=d.id;result.documentPath=String(d.fullName.fsName);result.phase=s.phase;
  return JournalRegressionSnapshot.json(result);
 }catch(e){return JournalRegressionSnapshot.json({status:'failed',error:String(e),line:e.line,fullArticleAcceptance:false});}
 finally{app.scriptPreferences.userInteractionLevel=ui;app.scriptPreferences.enableRedraw=redraw;}
})(GapStageJob);
'@
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ReportPath)))
[IO.File]::WriteAllText([IO.Path]::ChangeExtension($ReportPath,'.jsx'),$code,[Text.UTF8Encoding]::new($false))
if($PlanOnly){@{status='plan-only';codePath=[IO.Path]::ChangeExtension($ReportPath,'.jsx');adobeCalled=$false}|ConvertTo-Json;return}
$app=New-Object -ComObject InDesign.Application.2020
try{$result=([string](Invoke-JournalInDesignScript -Application $app -Code $code))|ConvertFrom-Json}catch{$result=[pscustomobject]@{status='failed';error=$_.Exception.Message;fullArticleAcceptance=$false}}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ReportPath)))
$result|Add-Member moduleSha256 @{}
foreach($moduleName in @('Invoke-JournalGapStage.ps1','journal_gap_solver.jsxinc','journal_gap_layout.jsxinc','journal_layout_rules.jsxinc','journal_layout_measurement.jsxinc')){$result.moduleSha256[$moduleName]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $moduleName) -Algorithm SHA256).Hash}
$result|Add-Member configSha256 (Get-FileHash -LiteralPath $ConfigPath -Algorithm SHA256).Hash
$result|Add-Member documentSha256 (Get-FileHash -LiteralPath $c.documentPath -Algorithm SHA256).Hash
[IO.File]::WriteAllText($ReportPath,($result|ConvertTo-Json -Depth 80),[Text.UTF8Encoding]::new($false))
if($result.status -ne 'gap-check-passed'){throw "GAP_STAGE_BLOCKED $ReportPath"}
$result
