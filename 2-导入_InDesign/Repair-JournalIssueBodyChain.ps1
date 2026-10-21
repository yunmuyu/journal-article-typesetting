#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DocumentPath,
    [Parameter(Mandatory)][int]$StartPageIndex,
    [Parameter(Mandatory)][int]$EndPageIndex,
    [Parameter(Mandatory)][string]$ResultPath
)
$ErrorActionPreference='Stop'
$document=(Get-Item -LiteralPath $DocumentPath).FullName
if([IO.Path]::GetFileName($document) -notmatch '(?i)QA|copy|副本'){throw 'BODY_CHAIN_QA_REQUIRED'}
if($StartPageIndex -lt 0 -or $EndPageIndex -lt $StartPageIndex){throw 'BODY_CHAIN_PAGE_RANGE'}
Import-Module (Join-Path $PSScriptRoot 'JournalInDesignScript.psm1') -Force
$job=@{path=$document;first=$StartPageIndex;last=$EndPageIndex}|ConvertTo-Json -Compress
$code=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_document_session.jsxinc'),[Text.Encoding]::UTF8)+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_regression_snapshot.jsxinc'),[Text.Encoding]::UTF8)+"var BodyChainJob=$job;"+@'
var __bodyChainResult=(function(job){
 var session=null,d=null,old=app.scriptPreferences.userInteractionLevel,result;
 try{
  app.scriptPreferences.userInteractionLevel=UserInteractionLevels.NEVER_INTERACT;
  session=JournalDocumentSession.acquire(app,job.path);d=session.document;
  if(d.modified)throw Error('BODY_CHAIN_TARGET_UNSAVED');
  if(job.last>=d.pages.length)throw Error('BODY_CHAIN_PAGE_RANGE');
  var frames=[],seen={},stories={},oldText={},perPage=[];
  for(var si=0;si<d.stories.length;si++)oldText[d.stories[si].id]=String(d.stories[si].contents);
  for(var pi=job.first;pi<=job.last;pi++){
   var items=d.pages[pi].allPageItems,count=0;
   for(var ii=0;ii<items.length;ii++){
    var f=items[ii];if(f.constructor.name!=='TextFrame'||seen[f.id])continue;
    var st=f.parentStory;if(st.extractLabel('journal-role')!=='body')continue;
    if(String(st.contents).replace(/\s/g,'')!=='')throw Error('BODY_CHAIN_CONTENT_PRESENT '+st.id);
    for(var ci=0;ci<st.textContainers.length;ci++){
     var p=st.textContainers[ci].parentPage;
     if(!p||p.documentOffset<job.first||p.documentOffset>job.last)throw Error('BODY_CHAIN_OUTSIDE_RANGE '+st.id);
    }
    seen[f.id]=true;stories[st.id]=true;frames.push(f);count++;
   }
   if(!count)throw Error('BODY_CHAIN_PAGE_WITHOUT_FRAME '+pi);
   perPage.push({index:pi,name:String(d.pages[pi].name),frames:count});
  }
  frames.sort(function(a,b){var pa=a.parentPage.documentOffset,pb=b.parentPage.documentOffset;if(pa!==pb)return pa-pb;var ay=a.geometricBounds[0],by=b.geometricBounds[0];if(Math.abs(ay-by)>.01)return ay-by;return a.geometricBounds[1]-b.geometricBounds[1];});
  if(frames.length<2)throw Error('BODY_CHAIN_FRAME_COUNT');
  var reuse=true,first=frames[0].parentStory;
  if(first.textContainers.length!==frames.length)reuse=false;
  else for(var fi=0;fi<frames.length;fi++)if(first.textContainers[fi].id!==frames[fi].id)reuse=false;
  if(!reuse){
   for(var fi=0;fi<frames.length;fi++){frames[fi].nextTextFrame=NothingEnum.NOTHING;frames[fi].previousTextFrame=NothingEnum.NOTHING;}
   for(var fi=0;fi<frames.length-1;fi++)frames[fi].nextTextFrame=frames[fi+1];
  }
  var body=frames[0].parentStory;body.insertLabel('journal-role','body');body.insertLabel('journal-template-contract',d.extractLabel('journal-template-contract'));
  d.recompose();
  if(body.textContainers.length!==frames.length)throw Error('BODY_CHAIN_LINK_COUNT');
  for(var fi=0;fi<frames.length;fi++)if(frames[fi].parentStory.id!==body.id)throw Error('BODY_CHAIN_NOT_UNIFIED');
  for(var si=0;si<d.stories.length;si++){
   var st=d.stories[si];if(st.id===body.id||stories[st.id])continue;
   if(oldText[st.id]!==undefined&&oldText[st.id]!==String(st.contents))throw Error('BODY_CHAIN_OTHER_TEXT_CHANGED '+st.id);
  }
  if(!reuse)d.save();
  result={passed:true,status:reuse?'reused':'repaired',pages:d.pages.length,articlePageRange:[job.first,job.last],bodyStoryId:body.id,frames:frames.length,pageFrames:perPage,otherStoryTextPreserved:true};
 }catch(e){result={passed:false,status:'failed',error:String(e),line:e.line};}
 finally{
  if(session&&session.openedHere){try{JournalDocumentSession.close(d,session,SaveOptions.NO);}catch(e){result={passed:false,status:'failed',error:'BODY_CHAIN_CLOSE '+e};}}
  app.scriptPreferences.userInteractionLevel=old;
 }
 return JournalRegressionSnapshot.json(result);
})(BodyChainJob);
__bodyChainResult;
'@
$app=New-Object -ComObject InDesign.Application.2020
$raw=[string](Invoke-JournalInDesignScript -Application $app -Code $code)
if([string]::IsNullOrWhiteSpace($raw)){throw 'BODY_CHAIN_NO_RESULT'}
$result=$raw|ConvertFrom-Json
[IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath),($result|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
if(-not $result.passed){throw "BODY_CHAIN_FAILED $raw"}
$result|ConvertTo-Json -Depth 10
