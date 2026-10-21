param(
    [Parameter(Mandatory=$true)][string]$ConfigPath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [Parameter(Mandatory=$true)][int]$DocumentId,
    [Parameter(Mandatory=$true)][string]$QueueDirectory,
    [Parameter(Mandatory=$true)][string]$LeaseId,
    [string]$DiagnosticDirectory,
    [int[]]$DiagnosticPages=@(),
    [string]$TrackingRequestPath
)
Import-Module (Join-Path $PSScriptRoot 'JournalInDesignScript.psm1') -Force
$ErrorActionPreference='Stop'
$lease=Get-Content -LiteralPath (Join-Path $QueueDirectory 'locks/indesign.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($lease.leaseId -ne $LeaseId){throw 'INDESIGN_LEASE_MISMATCH'}
$config=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$tracking=@()
if($TrackingRequestPath){$tracking=@(Get-Content -LiteralPath $TrackingRequestPath -Raw -Encoding UTF8|ConvertFrom-Json)}
$spec=@{config=$config;outputPath=$OutputPath;documentId=$DocumentId;diagnosticDirectory=$DiagnosticDirectory;diagnosticPages=@($DiagnosticPages);trackingRequests=$tracking} | ConvertTo-Json -Depth 80 -Compress
if($DiagnosticDirectory){New-Item -ItemType Directory -Path $DiagnosticDirectory -Force | Out-Null}
$modules=@('journal_document_session.jsxinc','journal_layout_rules.jsxinc','journal_regression_snapshot.jsxinc','journal_layout_measurement.jsxinc')
$jsx=($modules|ForEach-Object{[IO.File]::ReadAllText((Join-Path $PSScriptRoot $_),[Text.Encoding]::UTF8)}) -join "`n"
$jsx+=@"
var measurementAnswer;
try{measurementAnswer=(function(){
 var spec=$spec,s=JournalDocumentSession.acquire(app,spec.config.documentPath),d=s.document;
 if(d.id!==spec.documentId)throw Error('DOCUMENT_ID_CHANGED');
 var oldUI=app.scriptPreferences.userInteractionLevel,oldRedraw=app.scriptPreferences.enableRedraw;
 try{
  app.scriptPreferences.userInteractionLevel=UserInteractionLevels.NEVER_INTERACT;app.scriptPreferences.enableRedraw=false;
  var probes=spec.trackingRequests.length?JournalLayoutMeasurement.probeTracking(d,spec.trackingRequests):[];
  var result=JournalLayoutMeasurement.capture(d,spec.config),images=[];result.trackingProbes=probes;
  if(spec.diagnosticDirectory){
   var prefs=app.jpegExportPreferences,old=prefs.properties;
   try{
    prefs.exportResolution=150;prefs.jpegQuality=JPEGOptionsQuality.HIGH;prefs.exportingSpread=false;
    prefs.jpegExportRange=ExportRangeOrAllPages.EXPORT_RANGE;
    for(var i=0;i<spec.diagnosticPages.length;i++){
     var p=spec.diagnosticPages[i];if(p<0||p>=d.pages.length)throw Error('DIAGNOSTIC_PAGE_RANGE');
     var path=spec.diagnosticDirectory+'/diagnostic-page-'+(p+1)+'.jpg';
     prefs.pageString=d.pages[p].name;d.exportFile(ExportFormat.JPG,File(path),false);images.push(path);
    }
   }finally{prefs.properties=old;}
  }
  result.diagnostics={acceptance:false,purpose:'development-layout-diagnosis',images:images};
  var file=File(spec.outputPath);file.encoding='UTF-8';if(!file.open('w'))throw Error('MEASUREMENT_WRITE');
  file.write(JournalRegressionSnapshot.json(result));file.close();
  return 'MEASUREMENT_OK frames='+result.frames.length+' images='+images.length;
 }finally{app.scriptPreferences.userInteractionLevel=oldUI;app.scriptPreferences.enableRedraw=oldRedraw;}
}());}catch(e){measurementAnswer='ERROR '+e+' LINE '+e.line;}
measurementAnswer;
"@
$process=Get-Process InDesign -ErrorAction Stop | Select-Object -First 1
if(-not $process.Responding -or $process.MainWindowTitle -match '^(Script Alert|脚本警告|警告)'){throw 'INDESIGN_BLOCKED'}
$app=New-Object -ComObject 'InDesign.Application.2020'
$answer=[string](Invoke-JournalInDesignScript -Application $app -Code ($jsx))
if($answer -notlike 'MEASUREMENT_OK*'){throw $answer}
$answer
