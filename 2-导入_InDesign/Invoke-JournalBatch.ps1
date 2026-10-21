param(
    [Parameter(Mandatory=$true)][ValidateSet('Register','Preflight','Acquire','Complete','Release','Pass','Advance','RecordTiming','Checkpoint','Resume','Rework','Show')][string]$Action,
    [Parameter(Mandatory=$true)][string]$QueueDirectory,
    [string]$TaskPath,
    [string]$TaskId,
    [ValidateSet('InDesign','Illustrator')][string]$Lane='InDesign',
    [string]$LeaseId,
    [string]$EvidencePath,
    [string]$CheckpointDataPath,
    [string]$CheckpointPath,
    [ValidateSet('key-pages-approved','full-article-approved','merged')][string]$Stage,
    [ValidateSet('WordExtraction','Preflight','FormulaProcessing','InDesignAssembly','KeyPreview','FullExport','Merge')][string]$TimingStage,
    [long]$ElapsedMs=-1
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'JournalPreflight.psm1') -Force
$queue=[IO.Path]::GetFullPath($QueueDirectory);$tasksDir=Join-Path $queue 'tasks';$locksDir=Join-Path $queue 'locks';$checkpointsDir=Join-Path $queue 'checkpoints'
foreach($folder in @($queue,$tasksDir,$locksDir,$checkpointsDir)){if(-not(Test-Path -LiteralPath $folder)){[void](New-Item -ItemType Directory -Path $folder)}}

function TaskFile([string]$Id){Join-Path $tasksDir ($Id+'.json')}
function ReadTask([string]$Id){Read-JournalJson (TaskFile $Id)}
function LockFile([string]$Name){Join-Path $locksDir ($Name.ToLowerInvariant()+'.json')}
function StageLabel([string]$Name){
    switch($Name){
        'extracted'{'已提取'};'figures-approved'{'图源通过'};'formulas-approved'{'公式通过'}
        'initial-layout-complete'{'初排完成'};'key-pages-approved'{'关键页通过'}
        'full-article-approved'{'整篇通过'};'merged'{'已合入'}
        default{$Name}
    }
}
function EnsureRecord([object]$Record){
    if(-not $Record.PSObject.Properties['workflowStage']){
        $derived=switch([string]$Record.status){'ready'{'formulas-approved'};'layout'{'formulas-approved'};'rereview'{'initial-layout-complete'};'passed'{'full-article-approved'};'merged'{'merged'};default{'extracted'}}
        $Record|Add-Member -NotePropertyName workflowStage -NotePropertyValue $derived
    }
    $Record|Add-Member -NotePropertyName stageLabel -NotePropertyValue (StageLabel $Record.workflowStage) -Force
    if(-not $Record.PSObject.Properties['history']){$Record|Add-Member -NotePropertyName history -NotePropertyValue @()}
    if(-not $Record.PSObject.Properties['timings']){$Record|Add-Member -NotePropertyName timings -NotePropertyValue ([pscustomobject]@{})}
    foreach($timingName in @('wordExtractionMs','preflightMs','formulaProcessingMs','indesignAssemblyMs','keyPreviewMs','fullExportMs','mergeMs')){if(-not $Record.timings.PSObject.Properties[$timingName]){$Record.timings|Add-Member -NotePropertyName $timingName -NotePropertyValue $null}}
    $Record
}
function SaveTask([object]$Task){$Task=EnsureRecord $Task;Write-JournalJsonAtomic $Task (TaskFile $Task.taskId)}
function AddStage([object]$Record,[string]$Name,[string]$Event,[Nullable[long]]$Duration){
    $Record.workflowStage=$Name;$Record.stageLabel=StageLabel $Name;$Record.updatedAt=(Get-Date).ToString('o')
    $entry=[ordered]@{at=$Record.updatedAt;event=$Event;status=$Record.status;workflowStage=$Name;stageLabel=$Record.stageLabel}
    if($null -ne $Duration){$entry.elapsedMs=[long]$Duration}
    $Record.history+=@([pscustomobject]$entry)
}
function SetTiming([object]$Record,[string]$Name,[long]$Duration){
    $property=switch($Name){'WordExtraction'{'wordExtractionMs'};'Preflight'{'preflightMs'};'FormulaProcessing'{'formulaProcessingMs'};'InDesignAssembly'{'indesignAssemblyMs'};'KeyPreview'{'keyPreviewMs'};'FullExport'{'fullExportMs'};'Merge'{'mergeMs'}}
    $Record.timings.$property=$Duration
}
function RequiredCheckpointText([object]$State,[string]$Name){
    if(-not $State.PSObject.Properties[$Name] -or -not [string]$State.$Name){throw "CHECKPOINT_FIELD_MISSING: $Name"}
    [string]$State.$Name
}
function ResolveCheckpointInput([object]$InputRecord){
    if(-not $InputRecord.PSObject.Properties['name'] -or -not [string]$InputRecord.name){throw 'CHECKPOINT_INPUT_INVALID: name is required'}
    if(-not $InputRecord.PSObject.Properties['path'] -or -not [string]$InputRecord.path){throw "CHECKPOINT_INPUT_INVALID: path is required for $($InputRecord.name)"}
    $path=[IO.Path]::GetFullPath([string]$InputRecord.path)
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "CHECKPOINT_INPUT_MISSING: $path"}
    $sha=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if($InputRecord.PSObject.Properties['sha256'] -and [string]$InputRecord.sha256 -and ([string]$InputRecord.sha256).ToLowerInvariant() -ne $sha){throw "CHECKPOINT_INPUT_CHANGED: $path"}
    [pscustomobject][ordered]@{name=[string]$InputRecord.name;path=(Get-Item -LiteralPath $path).FullName;sha256=$sha}
}
function NormalizeCheckpoint([object]$State,[string]$ExpectedTaskId,[bool]$PreserveSavedAt=$false){
    if(-not $State.PSObject.Properties['schemaVersion'] -or [int]$State.schemaVersion -ne 1){throw 'CHECKPOINT_SCHEMA_UNSUPPORTED: expected schemaVersion 1'}
    $stateTaskId=RequiredCheckpointText $State 'taskId';if($stateTaskId -ne $ExpectedTaskId){throw "CHECKPOINT_TASK_MISMATCH: expected $ExpectedTaskId, got $stateTaskId"}
    if(-not $State.PSObject.Properties['currentTemplate']){throw 'CHECKPOINT_FIELD_MISSING: currentTemplate'}
    $templateVersion=RequiredCheckpointText $State.currentTemplate 'version';$templateStatus=RequiredCheckpointText $State.currentTemplate 'status'
    $inputs=@($State.inputs);if(-not $inputs.Count){throw 'CHECKPOINT_FIELD_MISSING: inputs'}
    $resolvedInputs=@($inputs|ForEach-Object{ResolveCheckpointInput $_})
    $failure=if($State.PSObject.Properties['failure'] -and $null -ne $State.failure){[ordered]@{classification=if($State.failure.PSObject.Properties['classification']){$State.failure.classification}else{$null};reason=if($State.failure.PSObject.Properties['reason']){$State.failure.reason}else{$null}}}else{[ordered]@{classification=$null;reason=$null}}
    [pscustomobject][ordered]@{
        schemaVersion=1;taskId=$stateTaskId
        currentTemplate=[ordered]@{version=$templateVersion;status=$templateStatus}
        currentArticle=(RequiredCheckpointText $State 'currentArticle');stage=(RequiredCheckpointText $State 'stage')
        inputs=$resolvedInputs;outputPath=[IO.Path]::GetFullPath((RequiredCheckpointText $State 'outputPath'))
        rulesVersion=(RequiredCheckpointText $State 'rulesVersion');configVersion=(RequiredCheckpointText $State 'configVersion')
        failure=$failure;nextAction=(RequiredCheckpointText $State 'nextAction')
        forbiddenReuse=@(if($State.PSObject.Properties['forbiddenReuse']){$State.forbiddenReuse}else{@()})
        savedAt=if($PreserveSavedAt -and $State.PSObject.Properties['savedAt'] -and [string]$State.savedAt){[string]$State.savedAt}else{(Get-Date).ToUniversalTime().ToString('o')}
    }
}

if($Action -eq 'Register'){
    $started=[Diagnostics.Stopwatch]::StartNew();$manifest=Read-JournalJson $TaskPath;$existing=if(Test-Path -LiteralPath (TaskFile $manifest.taskId)){EnsureRecord (ReadTask $manifest.taskId)}else{$null}
    $record=[ordered]@{taskId=$manifest.taskId;status=if($existing){$existing.status}else{'preflight'};workflowStage=if($existing){$existing.workflowStage}else{'extracted'};stageLabel=if($existing){$existing.stageLabel}else{'已提取'};manifestPath=(Get-Item -LiteralPath $TaskPath).FullName;manifestSha256=(Get-FileHash -LiteralPath $TaskPath -Algorithm SHA256).Hash;planPath=if($existing){$existing.planPath}else{$null};formulaReady=if($existing){[bool]$existing.formulaReady}else{$false};evidencePath=if($existing -and $existing.PSObject.Properties['evidencePath']){$existing.evidencePath}else{$null};checkpointPath=if($existing -and $existing.PSObject.Properties['checkpointPath']){$existing.checkpointPath}else{$null};checkpointSha256=if($existing -and $existing.PSObject.Properties['checkpointSha256']){$existing.checkpointSha256}else{$null};updatedAt=(Get-Date).ToString('o');timings=if($existing){$existing.timings}else{[pscustomobject]@{wordExtractionMs=$null;preflightMs=$null;formulaProcessingMs=$null;indesignAssemblyMs=$null;keyPreviewMs=$null;fullExportMs=$null;mergeMs=$null}};history=if($existing){@($existing.history)}else{@()}}
    if($manifest.PSObject.Properties['timings'] -and $manifest.timings.PSObject.Properties['wordExtractionMs']){$record.timings.wordExtractionMs=[long]$manifest.timings.wordExtractionMs}
    if($existing -and $existing.manifestSha256 -ne $record.manifestSha256){$record.status='preflight';$record.workflowStage='extracted';$record.stageLabel='已提取';$record.formulaReady=$false;$record.checkpointPath=$null;$record.checkpointSha256=$null}
    $started.Stop();$record.history+=@([pscustomobject]@{at=(Get-Date).ToString('o');event='registered';status=$record.status;workflowStage=$record.workflowStage;stageLabel=$record.stageLabel;elapsedMs=$started.ElapsedMilliseconds})
    SaveTask ([pscustomobject]$record);[pscustomobject]$record|ConvertTo-Json -Depth 30;exit
}
if($Action -eq 'Preflight'){
    $timer=[Diagnostics.Stopwatch]::StartNew();$record=EnsureRecord (ReadTask $TaskId);$manifest=Read-JournalJson $record.manifestPath;$planPath=Join-Path $manifest.outputDirectory 'layout-plan.json';$plan=New-JournalPreflightPlan $manifest;Write-JournalJsonAtomic $plan $planPath;$timer.Stop()
    $record.planPath=$planPath;$record.status=$plan.status;SetTiming $record 'Preflight' $timer.ElapsedMilliseconds
    if($plan.status -eq 'needs_input'){$record.updatedAt=(Get-Date).ToString('o');$record.history+=@([pscustomobject]@{at=$record.updatedAt;event='preflight-needs-input';status=$record.status;workflowStage=$record.workflowStage;stageLabel=$record.stageLabel;issues=$plan.issues.Count;elapsedMs=$timer.ElapsedMilliseconds})}
    else{AddStage $record 'figures-approved' 'figures-approved' $timer.ElapsedMilliseconds;if([int]$plan.counts.formulas -eq 0){$record.formulaReady=$true;AddStage $record 'formulas-approved' 'formulas-not-required' ([Nullable[long]]$null)}}
    SaveTask $record;$record|ConvertTo-Json -Depth 30;if($record.status -eq 'needs_input'){exit 2};exit
}
if($Action -eq 'Rework'){
    if(-not $TaskId){throw 'REWORK_TASK_REQUIRED'}
    $record=EnsureRecord (ReadTask $TaskId)
    if($record.status -notin @('rereview','passed','merged')){throw "REWORK_STATE $($record.status)"}
    foreach($heldFile in @(Get-ChildItem -LiteralPath $locksDir -Filter '*.json')){if((Read-JournalJson $heldFile.FullName).taskId -eq $TaskId){throw 'REWORK_ACTIVE_LEASE'}}
    $backupDirectory=Join-Path $queue 'rework-history';if(-not(Test-Path -LiteralPath $backupDirectory)){[void](New-Item -ItemType Directory -Path $backupDirectory)}
    Copy-Item -LiteralPath (TaskFile $TaskId) -Destination (Join-Path $backupDirectory ($TaskId+'-'+[guid]::NewGuid().ToString('N')+'.json'))
    foreach($field in @('evidencePath','checkpointPath','checkpointSha256')){$record|Add-Member -NotePropertyName $field -NotePropertyValue $null -Force}
    if($record.formulaReady){$record.status='ready';AddStage $record 'formulas-approved' 'rework-requested' ([Nullable[long]]$null)}
    else{$record.status='preflight';AddStage $record 'extracted' 'rework-requested' ([Nullable[long]]$null)}
    SaveTask $record;$record|ConvertTo-Json -Depth 30;exit
}
if($Action -eq 'Acquire'){
    $lock=LockFile $Lane;if(Test-Path -LiteralPath $lock){$held=Read-JournalJson $lock;throw "$Lane lane is held by $($held.taskId) since $($held.acquiredAt)"}
    $candidates=@(Get-ChildItem -LiteralPath $tasksDir -Filter '*.json'|ForEach-Object{EnsureRecord (Read-JournalJson $_.FullName)}|Where-Object{$_.status -eq 'ready'}|Where-Object{
        if($Lane -eq 'InDesign'){return $_.workflowStage -eq 'formulas-approved'}
        if($_.formulaReady -or -not $_.planPath -or -not(Test-Path -LiteralPath $_.planPath)){return $false}
        return [int](Read-JournalJson $_.planPath).counts.formulas -gt 0
    }|Sort-Object updatedAt)
    if($TaskId){$candidates=@($candidates|Where-Object{$_.taskId -eq $TaskId})};if(-not $candidates.Count){throw 'No ready task is available'};$record=$candidates[0]
    if($Lane -eq 'InDesign'){$plan=Read-JournalJson $record.planPath;if($plan.counts.formulas -gt 0 -and -not $record.formulaReady){throw 'Formula assets are not ready; acquire Illustrator first'};if($record.workflowStage -ne 'formulas-approved'){throw "Task is not ready for layout: $($record.workflowStage)"};$record.status='layout';SaveTask $record}
    $lease=[ordered]@{lane=$Lane;taskId=$record.taskId;leaseId=[guid]::NewGuid().ToString('N');acquiredAt=(Get-Date).ToUniversalTime().ToString('o');processId=$PID};Write-JournalJsonAtomic ([pscustomobject]$lease) $lock;[pscustomobject]$lease|ConvertTo-Json;exit
}
if($Action -in @('Complete','Release')){
    $lock=LockFile $Lane;if(-not(Test-Path -LiteralPath $lock)){throw "$Lane lane is not held"};$lease=Read-JournalJson $lock;if($lease.leaseId -ne $LeaseId){throw 'Lease id does not match'};$record=EnsureRecord (ReadTask $lease.taskId);$duration=[long]([DateTimeOffset]::UtcNow-([DateTimeOffset]$lease.acquiredAt)).TotalMilliseconds
    if($Action -eq 'Complete'){
        if($Lane -eq 'Illustrator'){$record.formulaReady=$true;$record.status='ready';SetTiming $record 'FormulaProcessing' $duration;AddStage $record 'formulas-approved' 'completed-Illustrator' $duration}
        else{$record.status='rereview';SetTiming $record 'InDesignAssembly' $duration;AddStage $record 'initial-layout-complete' 'completed-InDesign' $duration}
    }elseif($Lane -eq 'InDesign' -and $record.status -eq 'layout'){$record.status='ready';AddStage $record 'formulas-approved' 'released-InDesign' $duration}
    else{$record.updatedAt=(Get-Date).ToString('o');$record.history+=@([pscustomobject]@{at=$record.updatedAt;event="released-$Lane";status=$record.status;workflowStage=$record.workflowStage;stageLabel=$record.stageLabel;elapsedMs=$duration})}
    SaveTask $record;Remove-Item -LiteralPath $lock -Force;[pscustomobject]@{released=$true;lane=$Lane;taskId=$record.taskId;status=$record.status;workflowStage=$record.workflowStage;stageLabel=$record.stageLabel}|ConvertTo-Json;exit
}
if($Action -eq 'Advance'){
    $record=EnsureRecord (ReadTask $TaskId);$expected=switch($Stage){'key-pages-approved'{'initial-layout-complete'};'full-article-approved'{'key-pages-approved'};'merged'{'full-article-approved'}}
    if($record.workflowStage -ne $expected){throw "Cannot advance from $($record.workflowStage) to $Stage"};if(-not $EvidencePath -or -not(Test-Path -LiteralPath $EvidencePath -PathType Leaf)){throw 'Evidence file is required for workflow advancement'}
    $duration=if($ElapsedMs -ge 0){$ElapsedMs}else{0};$timing=switch($Stage){'key-pages-approved'{'KeyPreview'};'full-article-approved'{'FullExport'};'merged'{'Merge'}};SetTiming $record $timing $duration
    $record.status=switch($Stage){'full-article-approved'{'passed'};'merged'{'merged'};default{'rereview'}};$record|Add-Member -NotePropertyName evidencePath -NotePropertyValue (Get-Item -LiteralPath $EvidencePath).FullName -Force;AddStage $record $Stage "advanced-$Stage" $duration;SaveTask $record;$record|ConvertTo-Json -Depth 30;exit
}
if($Action -eq 'Pass'){
    $record=EnsureRecord (ReadTask $TaskId);if($record.workflowStage -notin @('initial-layout-complete','key-pages-approved')){throw 'Only reviewed layout tasks can pass'};if(-not $EvidencePath -or -not(Test-Path -LiteralPath $EvidencePath)){throw 'Review evidence is required'}
    if($record.workflowStage -eq 'initial-layout-complete'){AddStage $record 'key-pages-approved' 'key-pages-approved-by-pass' ([Nullable[long]]$null)};$record.status='passed';$record|Add-Member -NotePropertyName evidencePath -NotePropertyValue (Get-Item -LiteralPath $EvidencePath).FullName -Force;AddStage $record 'full-article-approved' 'passed' ([Nullable[long]]$null);SaveTask $record;$record|ConvertTo-Json -Depth 30;exit
}
if($Action -eq 'RecordTiming'){
    if(-not $TimingStage -or $ElapsedMs -lt 0){throw 'TimingStage and non-negative ElapsedMs are required'};$record=EnsureRecord (ReadTask $TaskId);SetTiming $record $TimingStage $ElapsedMs;$record.updatedAt=(Get-Date).ToString('o');$record.history+=@([pscustomobject]@{at=$record.updatedAt;event="timing-$TimingStage";status=$record.status;workflowStage=$record.workflowStage;stageLabel=$record.stageLabel;elapsedMs=$ElapsedMs});SaveTask $record;$record|ConvertTo-Json -Depth 30;exit
}
if($Action -eq 'Checkpoint'){
    if(-not $TaskId){throw 'TaskId is required for Checkpoint'}
    if(-not $CheckpointDataPath){throw 'CheckpointDataPath is required for Checkpoint'}
    $record=EnsureRecord (ReadTask $TaskId);$state=NormalizeCheckpoint (Read-JournalJson $CheckpointDataPath) $TaskId
    $target=if($CheckpointPath){[IO.Path]::GetFullPath($CheckpointPath)}else{Join-Path $checkpointsDir ($TaskId+'.json')}
    Write-JournalJsonAtomic $state $target;$checkpointSha=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
    $record|Add-Member -NotePropertyName checkpointPath -NotePropertyValue (Get-Item -LiteralPath $target).FullName -Force
    $record|Add-Member -NotePropertyName checkpointSha256 -NotePropertyValue $checkpointSha -Force
    $record.updatedAt=(Get-Date).ToString('o');$record.history+=@([pscustomobject]@{at=$record.updatedAt;event='checkpointed';status=$record.status;workflowStage=$record.workflowStage;stageLabel=$record.stageLabel;checkpointStage=$state.stage;nextAction=$state.nextAction})
    SaveTask $record;$state|ConvertTo-Json -Depth 30;exit
}
if($Action -eq 'Resume'){
    if(-not $TaskId){throw 'TaskId is required for Resume'}
    $record=EnsureRecord (ReadTask $TaskId)
    if(-not $record.PSObject.Properties['checkpointPath'] -or -not [string]$record.checkpointPath){throw 'CHECKPOINT_NOT_ATTACHED'}
    if(-not(Test-Path -LiteralPath $record.checkpointPath -PathType Leaf)){throw "CHECKPOINT_MISSING: $($record.checkpointPath)"}
    $actualCheckpointSha=(Get-FileHash -LiteralPath $record.checkpointPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if(-not $record.PSObject.Properties['checkpointSha256'] -or $actualCheckpointSha -ne ([string]$record.checkpointSha256).ToLowerInvariant()){throw 'CHECKPOINT_FILE_CHANGED'}
    $state=NormalizeCheckpoint (Read-JournalJson $record.checkpointPath) $TaskId $true
    $result=[ordered]@{};foreach($property in $state.PSObject.Properties){$result[$property.Name]=$property.Value}
    $result.verified=$true;$result.checkpointPath=$record.checkpointPath;$result.checkpointSha256=$actualCheckpointSha
    [pscustomobject]$result|ConvertTo-Json -Depth 30;exit
}
Get-ChildItem -LiteralPath $tasksDir -Filter '*.json'|ForEach-Object{EnsureRecord (Read-JournalJson $_.FullName)}|Sort-Object updatedAt|Select-Object taskId,status,workflowStage,stageLabel,formulaReady,updatedAt,planPath,checkpointPath,checkpointSha256,timings|ConvertTo-Json -Depth 10
