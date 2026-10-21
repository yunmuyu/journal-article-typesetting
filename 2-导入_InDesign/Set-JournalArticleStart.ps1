#Requires -Version 7.0
[CmdletBinding()]
param(
 [Parameter(Mandatory)][string]$DocumentPath,
 [Parameter(Mandatory)][int]$FirstPageIndex,
 [Parameter(Mandatory)][int]$StartPageNumber,
 [Parameter(Mandatory)][string]$ResultPath
)
$ErrorActionPreference='Stop'
$document=(Get-Item -LiteralPath $DocumentPath).FullName
if([IO.Path]::GetFileName($document) -notmatch '(?i)QA|copy|副本'){throw 'LEFT_START_QA_REQUIRED'}
if($FirstPageIndex -lt 0 -or $StartPageNumber -lt 2 -or $StartPageNumber%2){throw 'LEFT_START_EVEN_PAGE_REQUIRED'}
Import-Module (Join-Path $PSScriptRoot 'JournalInDesignScript.psm1') -Force
$job=@{path=$document;first=$FirstPageIndex;number=$StartPageNumber}|ConvertTo-Json -Compress
$code=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_document_session.jsxinc'),[Text.Encoding]::UTF8)+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_regression_snapshot.jsxinc'),[Text.Encoding]::UTF8)+"var LeftStartJob=$job;"+@'
var __leftStartResult=(function(job){var session=null,d=null,result;
 try{
  session=JournalDocumentSession.acquire(app,job.path);d=session.document;
  if(d.modified)throw Error('LEFT_START_UNSAVED_USER_CHANGES');
  var origin=Number(d.extractLabel('journal-article-page-origin'));
  if(!isFinite(origin)||origin<0||origin>=d.pages.length)throw Error('LEFT_START_ORIGIN');
  var first=d.pages[origin].getElements()[0],before={},prior=[],added=0;
  if(origin!==job.first&&!(String(first.name)===String(job.number)&&first.side===PageSideOptions.LEFT_HAND))throw Error('LEFT_START_SCOPE_CHANGED');
  for(var si=0;si<d.stories.length;si++)before[d.stories[si].id]=String(d.stories[si].contents);
  for(var pi=0;pi<origin;pi++)prior.push({id:d.pages[pi].id,name:String(d.pages[pi].name)});
  var unchanged=first.side===PageSideOptions.LEFT_HAND&&String(first.name)===String(job.number);
  if(!unchanged){
   if(first.side!==PageSideOptions.LEFT_HAND){var blank=d.pages.add(LocationOptions.BEFORE,first);blank.appliedMaster=NothingEnum.NOTHING;added=1;}
   var section=null;
   for(var xi=0;xi<d.sections.length;xi++)if(d.sections[xi].pageStart.id===first.id)section=d.sections[xi];
   if(!section)section=d.sections.add({pageStart:first});
   section.continueNumbering=false;section.pageNumberStart=job.number;section.sectionPrefix='';section.includeSectionPrefix=false;
   d.recompose();
  }
  if(first.side!==PageSideOptions.LEFT_HAND||String(first.name)!==String(job.number))throw Error('LEFT_START_POSTCONDITION');
  for(var pi=0;pi<prior.length;pi++)if(d.pages[pi].id!==prior[pi].id||String(d.pages[pi].name)!==prior[pi].name)throw Error('LEFT_START_PRIOR_PAGE_CHANGED '+pi+' expected='+prior[pi].id+'/'+prior[pi].name+' actual='+d.pages[pi].id+'/'+d.pages[pi].name);
  for(var si=0;si<d.stories.length;si++){var st=d.stories[si];if(before[st.id]!==undefined&&before[st.id]!==String(st.contents))throw Error('LEFT_START_TEXT_CHANGED');}
  d.insertLabel('journal-article-page-origin',String(first.documentOffset));
  if(!unchanged)d.save();
  result={passed:true,status:unchanged?'reused':'updated',pages:d.pages.length,firstPageIndex:first.documentOffset,firstPageNumber:String(first.name),firstPageSide:String(first.side),addedBlankPages:added,previousPageNumber:first.documentOffset?String(d.pages[first.documentOffset-1].name):null,allStoryTextPreserved:true,priorPagesPreserved:true};
 }catch(e){result={passed:false,error:String(e),line:e.line};}
 finally{if(session&&session.openedHere){try{JournalDocumentSession.close(d,session,SaveOptions.NO);}catch(e){result={passed:false,error:'LEFT_START_CLOSE '+e};}}}
 return JournalRegressionSnapshot.json(result);
})(LeftStartJob);
__leftStartResult;
'@
$app=New-Object -ComObject InDesign.Application.2020
$raw=[string](Invoke-JournalInDesignScript -Application $app -Code $code)
if([string]::IsNullOrWhiteSpace($raw)){throw 'LEFT_START_NO_RESULT'}
$result=$raw|ConvertFrom-Json
[IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath),($result|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
if(-not $result.passed){throw "LEFT_START_FAILED $raw"}
$result|ConvertTo-Json -Depth 8
