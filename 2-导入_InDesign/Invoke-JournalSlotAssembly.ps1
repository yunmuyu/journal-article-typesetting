param(
    [Parameter(Mandatory=$true)][string]$ConfigPath,
    [switch]$CloseWhenDone,
    [switch]$PlanOnly
)
Import-Module (Join-Path $PSScriptRoot 'JournalInDesignScript.psm1') -Force
$ErrorActionPreference='Stop'
$configFile=(Get-Item -LiteralPath $ConfigPath).FullName
$config=Get-Content -LiteralPath $configFile -Raw -Encoding UTF8|ConvertFrom-Json
$document=(Get-Item -LiteralPath $config.documentPath).FullName
if([IO.Path]::GetExtension($document) -ine '.indd'){throw 'documentPath must be an INDD document'}
if([IO.Path]::GetFileName($document) -notmatch '(QA|copy|副本)'){throw 'Only QA/copy/副本 documents are allowed'}
foreach($component in @($config.components)){
    if($component.mode -eq 'idms'){
        $componentPath=(Get-Item -LiteralPath $component.idmsPath).FullName
        if([IO.Path]::GetExtension($componentPath) -ine '.idms'){throw "Component must be IDMS: $componentPath"}
        if($component.sha256 -and (Get-FileHash -LiteralPath $componentPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne ([string]$component.sha256).ToLowerInvariant()){throw "Component changed: $componentPath"}
    }
}
$plan=[ordered]@{status='ready';documentPath=$document;slotCount=6;componentCount=@($config.components).Count;singleJsxCall=$true;createsFrontFrames=$false}
if($PlanOnly){$plan|ConvertTo-Json -Depth 5;return}
$front=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_frontmatter.jsxinc'),[Text.Encoding]::UTF8)
$slots=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_slot_template.jsxinc'),[Text.Encoding]::UTF8)
$configJson=$config|ConvertTo-Json -Depth 20 -Compress
$close=if($CloseWhenDone){'true'}else{'false'}
$script=$front+$slots+@"
var __slotAssemblyResult;
try {
 __slotAssemblyResult=app.doScript(function(){
  var job=$configJson,file=File(job.documentPath),wanted=String(file.fsName).toLowerCase(),d=null,opened=false,targetId=null;
  function documentPath(document){try{return String(document.fullName.fsName).toLowerCase();}catch(e){throw Error('TARGET_PATH_UNAVAILABLE');}}
  function closeExact(document,saveOption){if(!document||!document.isValid)throw Error('TARGET_DOCUMENT_INVALID');if(documentPath(document)!==wanted)throw Error('TARGET_PATH_CHANGED expected='+wanted+' actual='+documentPath(document));if(document.id!==targetId)throw Error('TARGET_ID_CHANGED expected='+targetId+' actual='+document.id);document.close(saveOption);}
  for(var i=0;i<app.documents.length;i++){try{if(String(app.documents[i].fullName.fsName).toLowerCase()===wanted){d=app.documents[i];break;}}catch(ignore){}}
  if(!d){d=app.open(file);opened=true;}targetId=d.id;if(documentPath(d)!==wanted)throw Error('TARGET_PATH_CHANGED expected='+wanted+' actual='+documentPath(d));
  var redraw=app.scriptPreferences.enableRedraw,preflight=d.preflightOptions.preflightOff;
  try{
   app.scriptPreferences.enableRedraw=false;d.preflightOptions.preflightOff=true;
   var result=JournalSlotTemplate.apply(d,job);d.recompose();d.preflightOptions.preflightOff=preflight;app.scriptPreferences.enableRedraw=redraw;d.save();
   if($close&&opened)closeExact(d,SaveOptions.YES);
   return 'SLOT_ASSEMBLY_OK '+(opened?'opened':'reused')+' '+result.components.length;
  }finally{app.scriptPreferences.enableRedraw=redraw;if(d.isValid)d.preflightOptions.preflightOff=preflight;}
 },ScriptLanguage.JAVASCRIPT,[],UndoModes.ENTIRE_SCRIPT,'Journal slot assembly');
} catch(e) {__slotAssemblyResult='ERROR '+e+' LINE '+e.line;}
__slotAssemblyResult;
"@
$process=Get-Process InDesign -ErrorAction SilentlyContinue|Select-Object -First 1
if($process -and (-not $process.Responding -or $process.MainWindowTitle -match '^(Script Alert|脚本警告|脚本提示|警告)')){throw "InDesign is blocked: $($process.MainWindowTitle)"}
$app=New-Object -ComObject 'InDesign.Application.2020'
$result=[string](Invoke-JournalInDesignScript -Application $app -Code ($script))
if(-not $result.StartsWith('SLOT_ASSEMBLY_OK')){throw $result}
$result
