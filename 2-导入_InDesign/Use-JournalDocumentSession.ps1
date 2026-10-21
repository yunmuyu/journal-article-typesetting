[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Open','Close')][string]$Action,
    [Parameter(Mandatory=$true)][string]$SessionPath,
    [string]$DocumentPath,
    [switch]$DiscardChanges
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'JournalInDesignScript.psm1') -Force
$processes=@(Get-Process InDesign -ErrorAction SilentlyContinue)
if($processes.Count -ne 1){throw 'INDESIGN_SINGLE_PROCESS_REQUIRED'}
$applicationProcessId=$processes[0].Id
if($Action -eq 'Open'){
    if(-not $DocumentPath -or [IO.Path]::GetFileName($DocumentPath) -notmatch '(QA|copy|副本)'){throw 'QA_PATH_REQUIRED'}
    if(Test-Path -LiteralPath $SessionPath){$prior=Get-Content -LiteralPath $SessionPath -Raw -Encoding UTF8|ConvertFrom-Json;if($prior.status -eq 'open'){throw 'DOCUMENT_SESSION_ALREADY_OPEN'}}
    $spec=@{action=$Action;path=[IO.Path]::GetFullPath($DocumentPath)}
}else{
    $prior=Get-Content -LiteralPath $SessionPath -Raw -Encoding UTF8|ConvertFrom-Json
    if($prior.status -ne 'open'){throw 'DOCUMENT_SESSION_NOT_OPEN'}
    if(-not $prior.PSObject.Properties['applicationProcessId'] -or $prior.applicationProcessId -ne $applicationProcessId){throw 'DOCUMENT_SESSION_APPLICATION_CHANGED'}
    $spec=@{action=$Action;path=$prior.path;id=$prior.documentId;openedHere=[bool]$prior.openedHere;discardChanges=[bool]$DiscardChanges}
}
$payload=$spec|ConvertTo-Json -Compress
$code=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_document_session.jsxinc'))+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_regression_snapshot.jsxinc'))+"var SessionRequest=$payload;"+@'
(function(s){try{var state,d;if(s.action==='Open'){state=JournalDocumentSession.acquire(app,s.path);d=state.document;return JournalRegressionSnapshot.json({status:'open',documentId:d.id,path:d.fullName.fsName,openedHere:state.openedHere});}d=app.documents.itemByID(s.id);state={id:s.id,path:JournalDocumentSession.normalizePath(s.path),openedHere:s.openedHere,closed:false};JournalDocumentSession.assertIdentity(d,state);if(s.openedHere&&!s.discardChanges){JournalDocumentSession.save(d,state);if(d.modified)throw Error('SAVE_INCOMPLETE');}var closed=JournalDocumentSession.close(d,state,SaveOptions.NO);return JournalRegressionSnapshot.json({status:'released',documentId:s.id,path:s.path,openedHere:s.openedHere,closed:closed,remaining:app.documents.length});}catch(e){return 'ERROR '+e+' LINE '+e.line;}})(SessionRequest);
'@
$app=New-Object -ComObject InDesign.Application.2020
$raw=[string](Invoke-JournalInDesignScript -Application $app -Code $code)
if(-not $raw -or $raw -eq 'null' -or $raw.StartsWith('ERROR')){throw "DOCUMENT_SESSION_FAILED $raw"}
$result=$raw|ConvertFrom-Json
$result|Add-Member -NotePropertyName applicationProcessId -NotePropertyValue $applicationProcessId -Force
if($result.status -notin @('open','released')){throw 'DOCUMENT_SESSION_RESULT_INVALID'}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($SessionPath)))
[IO.File]::WriteAllText([IO.Path]::GetFullPath($SessionPath),($result|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
$result
