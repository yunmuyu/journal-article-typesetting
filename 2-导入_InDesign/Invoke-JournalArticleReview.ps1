param(
    [Parameter(Mandatory=$true)][string]$ConfigPath,
    [Parameter(Mandatory=$true)][string]$QueueDirectory,
    [Parameter(Mandatory=$true)][string]$LeaseId,
    [ValidateRange(1,20)][int]$MaxAttempts=5,
    [switch]$PlanOnly
)
Import-Module (Join-Path $PSScriptRoot 'JournalInDesignScript.psm1') -Force
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$jobPath=(Get-Item -LiteralPath $ConfigPath).FullName
$jobDirectory=Split-Path -Parent $jobPath
$job=Get-Content -LiteralPath $jobPath -Raw -Encoding UTF8|ConvertFrom-Json
function ReadJson([string]$Path){Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}
function WriteJson([string]$Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 90),[Text.UTF8Encoding]::new($false))}
function SamePath([string]$First,[string]$Second){[IO.Path]::GetFullPath($First) -ieq [IO.Path]::GetFullPath($Second)}
function AssertLease{
    $lease=ReadJson (Join-Path $QueueDirectory 'locks/indesign.json')
    if($lease.leaseId -cne $LeaseId -or $lease.taskId -cne $job.taskId -or $lease.lane -ne 'InDesign'){throw 'REVIEW_INDESIGN_LEASE_MISMATCH'}
}
function Resolve-PageGrowthBudget($Job,$Assembly,$Audit,[int]$DocumentId){
    if(-not $Job.PSObject.Properties['allowPageGrowth'] -or $Job.allowPageGrowth -ne $true){return $null}
    if(-not $Assembly -or -not $Assembly.PSObject.Properties['pages'] -or $Assembly.pages -lt 1 -or [double]$Assembly.pages -ne [Math]::Floor([double]$Assembly.pages)){throw 'REVIEW_PAGE_GROWTH_RESULT_REQUIRED'}
    if($Assembly.documentId -ne $DocumentId -or -not(SamePath $Assembly.outputPath $Job.outputPath)){throw 'REVIEW_PAGE_GROWTH_IDENTITY'}
    if($Assembly.status -notin @('assembled-unchecked','normalized-unchecked','reflowed-unchecked','bottom-applied-unchecked','layout-applied-unchecked')){throw 'REVIEW_PAGE_GROWTH_RESULT_NOT_READY'}
    $allocated=if($Job.PSObject.Properties['expected'] -and $Job.expected.PSObject.Properties['pages']){[int]$Job.expected.pages}else{[int]$Audit.pageBudget}
    return [ordered]@{allocatedPages=$allocated;measuredPages=[int]$Assembly.pages;documentId=$DocumentId;assemblyResultPath=$Job.resultPath;reason='explicit-source-overflow-page-growth'}
}
AssertLease
if($job.schemaVersion -ne 1){throw 'REVIEW_JOB_VERSION'}
if(-not(Test-Path -LiteralPath $job.outputPath -PathType Leaf)){throw 'REVIEW_OUTPUT_MISSING'}
if([IO.Path]::GetFileName($job.outputPath) -notmatch '(?i)QA|copy|副本'){throw 'REVIEW_QA_REQUIRED'}
if(SamePath $job.outputPath $job.templatePath){throw 'REVIEW_SOURCE_OUTPUT_COLLISION'}
$audit=ReadJson $job.auditConfigPath
if(-not(SamePath $audit.documentPath $job.outputPath)){throw 'REVIEW_AUDIT_DOCUMENT_MISMATCH'}
if(-not $audit.configVersion -or -not $audit.templateContractVersion){throw 'REVIEW_AUDIT_CONTRACT_REQUIRED'}
$assembly=$null
if($job.PSObject.Properties['resultPath'] -and (Test-Path -LiteralPath $job.resultPath)){$assembly=ReadJson $job.resultPath}
$documentId=$null
if($job.PSObject.Properties['continuation'] -and $job.continuation -and $job.continuation.documentId){
    $documentId=[int]$job.continuation.documentId
    if(-not $job.continuation.outputSha256 -or (Get-FileHash -LiteralPath $job.outputPath -Algorithm SHA256).Hash -ine $job.continuation.outputSha256){throw 'REVIEW_CONTINUATION_OUTPUT_CHANGED'}
}elseif($assembly -and $assembly.documentId){
    if(-not(SamePath $assembly.outputPath $job.outputPath)){throw 'REVIEW_ASSEMBLY_DOCUMENT_MISMATCH'}
    if($assembly.status -notin @('assembled-unchecked','normalized-unchecked','reflowed-unchecked','bottom-applied-unchecked','layout-applied-unchecked')){throw 'REVIEW_ASSEMBLY_NOT_READY'}
    $documentId=[int]$assembly.documentId
}else{throw 'REVIEW_DOCUMENT_ID_REQUIRED'}
if($documentId -lt 1){throw 'REVIEW_DOCUMENT_ID_REQUIRED'}
$pageBudgetResolution=Resolve-PageGrowthBudget $job $assembly $audit $documentId
$needsBindings=@($audit.bindings).Count -eq 0
if($needsBindings -and (-not $assembly -or -not $assembly.PSObject.Properties['bindings'] -or -not @($assembly.bindings).Count)){throw 'REVIEW_ASSEMBLY_BINDINGS_REQUIRED'}
$refreshes=[Collections.Generic.List[object]]::new()
$approvedToolRoot=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')+'\'
foreach($entry in $job.inputs){
    $path=(Get-Item -LiteralPath $entry.path).FullName
    $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if($hash -ine $entry.sha256){
        if(-not $path.StartsWith($approvedToolRoot,[StringComparison]::OrdinalIgnoreCase)){throw "REVIEW_IMMUTABLE_INPUT_CHANGED $($entry.name)"}
        $refreshes.Add([ordered]@{name=$entry.name;path=$path;previousSHA256=$entry.sha256;currentSHA256=$hash;reason='current-installed-tool-source'})
    }
}
$required=@('Invoke-JournalArticleAssembly.ps1','Export-JournalLayoutMeasurement.ps1','New-JournalBottomPlan.ps1','Invoke-JournalLayout.ps1','journal_bottom_measurement_request.cjs','journal_tracking_request.cjs','journal_reflow_plan.cjs','complete_assembly_check_config.cjs','journal_regression_snapshot.jsxinc','Invoke-JournalGapStage.ps1','journal_gap_solver.jsxinc','journal_gap_layout.jsxinc')
foreach($name in $required){if(-not(Test-Path -LiteralPath (Join-Path $PSScriptRoot $name))){throw "REVIEW_DEPENDENCY_MISSING $name"}}
$node=(Get-Command node -ErrorAction Stop).Source
if($PlanOnly){[ordered]@{status='planned';configPath=$jobPath;documentPath=$job.outputPath;documentId=$documentId;needsBindings=$needsBindings;pageBudgetResolution=$pageBudgetResolution;maxAttempts=$MaxAttempts;requiredLayoutStages=@('NormalizeExisting','BeforeBottomGap','ApplyBottomExisting','AfterBottomGapAndContinuations','FullCheck');inputRefreshes=@($refreshes);humanReview='pending';adobeCalled=$false}|ConvertTo-Json -Depth 15;return}
$runDirectory=Join-Path $jobDirectory ('review-run-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runDirectory|Out-Null
WriteJson (Join-Path $runDirectory 'input-refreshes.json') @($refreshes)
$summaryPath=Join-Path $runDirectory 'review-summary.json'
$summary=[ordered]@{passed=$false;status='running';documentPath=$job.outputPath;documentId=$documentId;humanReview='pending';runDirectory=$runDirectory;attempts=0}
WriteJson $summaryPath $summary
function UpdateJobInputs($Value){
    foreach($entry in $Value.inputs){
        if($entry.name -eq 'audit-config'){$entry.path=$Value.auditConfigPath}
        $path=(Get-Item -LiteralPath $entry.path).FullName
        $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if($hash -ine $entry.sha256 -and $entry.name -ne 'audit-config' -and -not $path.StartsWith($approvedToolRoot,[StringComparison]::OrdinalIgnoreCase)){throw "REVIEW_IMMUTABLE_INPUT_CHANGED $($entry.name)"}
        $entry.sha256=$hash
    }
}
function InvokeNode([string]$Module,[string[]]$Arguments,[string]$LogPath){
    & $node (Join-Path $PSScriptRoot $Module) @Arguments 2>&1|Tee-Object -FilePath $LogPath
    if($LASTEXITCODE -ne 0){throw "REVIEW_NODE_FAILED $Module exit=$LASTEXITCODE"}
}
function WriteOperation([string]$Kind,[string]$PlanPath,[string]$Directory){
    $operation=$job|ConvertTo-Json -Depth 90|ConvertFrom-Json
    $operation|Add-Member continuation ([pscustomobject]@{documentId=$documentId;outputSha256=(Get-FileHash -LiteralPath $job.outputPath -Algorithm SHA256).Hash}) -Force
    $operation|Add-Member statePath (Join-Path $Directory "$Kind.state.json") -Force
    $operation|Add-Member resultPath (Join-Path $Directory "$Kind.result.json") -Force
    $property=if($Kind -eq 'bottom'){'bottomPlanPath'}else{'reflowPlanPath'}
    $operation|Add-Member $property $PlanPath -Force
    UpdateJobInputs $operation
    $operationPath=Join-Path $Directory "$Kind.job.json"
    WriteJson $operationPath $operation
    $operationPath
}
function AssertNativeIdentity($Application){
    AssertLease
    $spec=@{documentId=$documentId;path=$job.outputPath}|ConvertTo-Json -Compress
    $answer=[string](Invoke-JournalInDesignScript -Application $Application -Code ("(function(s){try{var d=app.documents.itemByID(s.documentId).getElements()[0];if(!d.isValid||String(d.fullName.fsName).toLowerCase()!==String(File(s.path).fsName).toLowerCase())throw Error('REVIEW_DOCUMENT_IDENTITY');return 'IDENTITY_OK';}catch(e){return 'ERROR '+e+' LINE '+e.line;}})($spec);"))
    if($answer -ne 'IDENTITY_OK'){throw $answer}
}
function PersistContinuation{
    $job|Add-Member continuation ([pscustomobject]@{documentId=$documentId;outputSha256=(Get-FileHash -LiteralPath $job.outputPath -Algorithm SHA256).Hash}) -Force
    UpdateJobInputs $job
    WriteJson $jobPath $job
}
function PrepareFirstPageGeometry($app){
    $reviewAudit=ReadJson $job.auditConfigPath
    if($reviewAudit.PSObject.Properties['refitFirstPageBeforeReview'] -and $reviewAudit.refitFirstPageBeforeReview){
        AssertNativeIdentity $app
        $spec=@{id=$documentId;path=$job.outputPath;config=$reviewAudit}|ConvertTo-Json -Depth 90 -Compress
        $helper=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_layout_rules.jsxinc'),[Text.Encoding]::UTF8)
        $code=$helper+@"
(function(s){var ui=app.scriptPreferences.userInteractionLevel,redraw=app.scriptPreferences.enableRedraw;try{app.scriptPreferences.userInteractionLevel=UserInteractionLevels.NEVER_INTERACT;app.scriptPreferences.enableRedraw=false;var d=app.documents.itemByID(s.id);if(!d.isValid||String(d.fullName.fsName).toLowerCase()!==String(File(s.path).fsName).toLowerCase())throw Error('REVIEW_DOCUMENT_IDENTITY');var before=[],i;for(i=0;i<d.stories.length;i++)before.push(String(d.stories[i].contents));JournalLayout.geometry(d,s.config);for(i=0;i<before.length;i++)if(String(d.stories[i].contents)!==before[i])throw Error('GEOMETRY_TEXT_CHANGED');d.save();return 'GEOMETRY_PREPARED';}catch(e){return 'ERROR '+e+' LINE '+e.line;}finally{app.scriptPreferences.userInteractionLevel=ui;app.scriptPreferences.enableRedraw=redraw;}})($spec);
"@
        $answer=[string](Invoke-JournalInDesignScript -Application $app -Code $code)
        $answer|Set-Content -LiteralPath (Join-Path $runDirectory 'first-page-geometry.log') -Encoding UTF8
        if($answer -ne 'GEOMETRY_PREPARED'){throw $answer}
        PersistContinuation
    }
}
try{
    $process=Get-Process InDesign -ErrorAction Stop|Select-Object -First 1
    if(-not $process.Responding -or $process.MainWindowTitle -match '^(Script Alert|脚本警告|警告)'){throw 'REVIEW_INDESIGN_BLOCKED'}
    $app=New-Object -ComObject 'InDesign.Application.2020'
    AssertNativeIdentity $app
    if($needsBindings){
        $snapshotPath=Join-Path $runDirectory 'initial.snapshot.json'
        $spec=@{documentId=$documentId;path=$job.outputPath;bindings=@($assembly.bindings);outputPath=$snapshotPath}|ConvertTo-Json -Depth 30 -Compress
        $helper=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_regression_snapshot.jsxinc'),[Text.Encoding]::UTF8)
        $code=$helper+@"
(function(){try{var s=$spec,d=app.documents.itemByID(s.documentId).getElements()[0];if(!d.isValid||String(d.fullName.fsName).toLowerCase()!==String(File(s.path).fsName).toLowerCase())throw Error('REVIEW_DOCUMENT_IDENTITY');s.articlePageRange=[0,d.pages.length-1];var r={candidate:JournalRegressionSnapshot.capture(d,s)},f=File(s.outputPath);f.encoding='UTF-8';if(!f.open('w'))throw Error('REVIEW_SNAPSHOT_WRITE');f.write(JournalRegressionSnapshot.json(r));f.close();return 'SNAPSHOT_OK';}catch(e){return 'ERROR '+e+' LINE '+e.line;}}());
"@
        $answer=[string](Invoke-JournalInDesignScript -Application $app -Code ($code))
        if($answer -ne 'SNAPSHOT_OK'){throw $answer}
        $boundAudit=Join-Path $runDirectory 'bound-audit.json'
        InvokeNode 'complete_assembly_check_config.cjs' @($jobPath,$snapshotPath,$boundAudit) (Join-Path $runDirectory 'derive-bindings.log')
        $job.auditConfigPath=$boundAudit
        PersistContinuation
    }
    if($pageBudgetResolution){
        $audit=ReadJson $job.auditConfigPath
        $audit.pageBudget=$pageBudgetResolution.measuredPages
        $audit|Add-Member pageBudgetResolution ([pscustomobject]$pageBudgetResolution) -Force
        $grownAudit=Join-Path $runDirectory 'page-growth.audit.json'
        WriteJson $grownAudit $audit
        $job.auditConfigPath=$grownAudit
        $summary['pageBudgetResolution']=$pageBudgetResolution
        PersistContinuation
    }
    AssertNativeIdentity $app
    if($job.PSObject.Properties['inPlace'] -and $job.inPlace -and $job.PSObject.Properties['articlePageRange']){throw 'REVIEW_MERGED_DETAILS_REQUIRES_SCOPED_ENTRY'}
    & (Join-Path $PSScriptRoot 'Invoke-JournalArticleAssembly.ps1') -ConfigPath $jobPath -Stage NormalizeExisting -QueueDirectory $QueueDirectory -LeaseId $LeaseId
    PersistContinuation
    PrepareFirstPageGeometry $app
    for($attempt=1;$attempt -le $MaxAttempts;$attempt++){
        $summary.attempts=$attempt;WriteJson $summaryPath $summary
        $directory=Join-Path $runDirectory ('attempt-'+$attempt);New-Item -ItemType Directory -Path $directory|Out-Null
        AssertNativeIdentity $app
        & (Join-Path $PSScriptRoot 'Invoke-JournalGapStage.ps1') -ConfigPath $job.auditConfigPath -DocumentId $documentId -ReportPath (Join-Path $directory 'gap-before.json') -Phase BeforeBottom
        PersistContinuation
        $measurement=Join-Path $directory 'measurement.json';$request=Join-Path $directory 'bottom.request.json';$plan=Join-Path $directory 'bottom.plan.json'
        & (Join-Path $PSScriptRoot 'Export-JournalLayoutMeasurement.ps1') -ConfigPath $job.auditConfigPath -OutputPath $measurement -DocumentId $documentId -QueueDirectory $QueueDirectory -LeaseId $LeaseId 2>&1|Tee-Object -FilePath (Join-Path $directory 'measurement.log')
        InvokeNode 'journal_bottom_measurement_request.cjs' @($measurement,$request) (Join-Path $directory 'bottom-request.log')
        try{& (Join-Path $PSScriptRoot 'New-JournalBottomPlan.ps1') -InputPath $request -OutputPath $plan 2>&1|Tee-Object -FilePath (Join-Path $directory 'bottom-plan.log')}catch{if(-not(Test-Path -LiteralPath $plan)){throw};$_.Exception.Message|Add-Content (Join-Path $directory 'bottom-plan.log')}
        $bottom=ReadJson $plan
        if($bottom.status -eq 'ready'){
            $operation=WriteOperation 'bottom' $plan $directory
            AssertNativeIdentity $app
            & (Join-Path $PSScriptRoot 'Invoke-JournalArticleAssembly.ps1') -ConfigPath $operation -Stage ApplyBottomExisting -QueueDirectory $QueueDirectory -LeaseId $LeaseId 2>&1|Tee-Object -FilePath (Join-Path $directory 'apply-bottom.log')
            $resolved=ReadJson $operation;$job.panels=$resolved.panels
            PersistContinuation
            AssertNativeIdentity $app
            & (Join-Path $PSScriptRoot 'Invoke-JournalGapStage.ps1') -ConfigPath $job.auditConfigPath -DocumentId $documentId -ReportPath (Join-Path $directory 'gap-after.json') -Phase AfterBottom
            PersistContinuation
            & (Join-Path $PSScriptRoot 'Invoke-JournalLayout.ps1') -ConfigPath $job.auditConfigPath -Mode Check -ExportPreview 2>&1|Tee-Object -FilePath (Join-Path $directory 'full-check.log')
            $audit=ReadJson $job.auditConfigPath
            $check=ReadJson ([IO.Path]::ChangeExtension($audit.auditPath,'.result.json'))
            WriteJson (Join-Path $directory 'full-check.result.json') $check
            if(-not $check.passed){throw 'REVIEW_FULL_CHECK_FAILED'}
            $summary.passed=$true;$summary.status='technical-check-passed';$summary['evidencePath']=[IO.Path]::ChangeExtension($audit.auditPath,'.result.json')
            WriteJson $summaryPath $summary
            $summary|ConvertTo-Json -Depth 15
            return
        }
        $tracking=Join-Path $directory 'tracking.request.json';$dryReflow=Join-Path $directory 'reflow.dry.json'
        $trackingBudget=if($attempt -eq $MaxAttempts){24}else{[Math]::Min(24,[Math]::Pow(2,$attempt))}
        InvokeNode 'journal_tracking_request.cjs' @($measurement,$plan,$tracking,[string]$trackingBudget) (Join-Path $directory 'tracking-request.log')
        InvokeNode 'journal_reflow_plan.cjs' @($measurement,$plan,$dryReflow) (Join-Path $directory 'dry-reflow.log')
        $dry=ReadJson $dryReflow;$requests=@(ReadJson $tracking)
        if($requests.Count -and -not @($dry.leadingCompression).Count -and -not @($dry.leadingExpansion).Count){
            AssertNativeIdentity $app
            & (Join-Path $PSScriptRoot 'Export-JournalLayoutMeasurement.ps1') -ConfigPath $job.auditConfigPath -OutputPath $measurement -DocumentId $documentId -QueueDirectory $QueueDirectory -LeaseId $LeaseId -TrackingRequestPath $tracking 2>&1|Tee-Object -FilePath (Join-Path $directory 'tracking-measurement.log')
        }
        $reflow=Join-Path $directory 'reflow.plan.json'
        InvokeNode 'journal_reflow_plan.cjs' @($measurement,$plan,$reflow) (Join-Path $directory 'reflow-plan.log')
        $candidate=ReadJson $reflow
        if(-not @($candidate.tracking).Count -and -not @($candidate.leadingCompression).Count -and -not @($candidate.leadingExpansion).Count -and -not @($bottom.deferred).Count){if($attempt -lt $MaxAttempts){continue};throw 'REVIEW_NO_REFLOW_PROGRESS'}
        $operation=WriteOperation 'reflow' $reflow $directory
        AssertNativeIdentity $app
        & (Join-Path $PSScriptRoot 'Invoke-JournalArticleAssembly.ps1') -ConfigPath $operation -Stage ReflowExisting -QueueDirectory $QueueDirectory -LeaseId $LeaseId 2>&1|Tee-Object -FilePath (Join-Path $directory 'apply-reflow.log')
        $resolved=ReadJson $operation;$job.panels=$resolved.panels
        PersistContinuation
        PrepareFirstPageGeometry $app
        AssertNativeIdentity $app
        & (Join-Path $PSScriptRoot 'Invoke-JournalGapStage.ps1') -ConfigPath $job.auditConfigPath -DocumentId $documentId -ReportPath (Join-Path $directory 'gap-after.json') -Phase AfterBottom
        PersistContinuation
        & (Join-Path $PSScriptRoot 'Invoke-JournalLayout.ps1') -ConfigPath $job.auditConfigPath -Mode Check -ExportPreview -AllowValidationFailure 2>&1|Tee-Object -FilePath (Join-Path $directory 'full-check.log')
        $audit=ReadJson $job.auditConfigPath
        $check=ReadJson ([IO.Path]::ChangeExtension($audit.auditPath,'.result.json'))
        WriteJson (Join-Path $directory 'full-check.result.json') $check
        if(-not $check.passed -and @($check.errors|Where-Object {$_ -notmatch '^(BOTTOM:|LAST_PAGE_BALANCE:|LOCAL_BOTTOM:|LARGE_EMPTY_REGION:|FOOTER_SPACING:|BODY_FRAME_WHITESPACE:)'}).Count){throw 'REVIEW_NON_LAYOUT_CHECK_FAILED'}
        if($check.passed){
            $summary.passed=$true;$summary.status='technical-check-passed';$summary['evidencePath']=[IO.Path]::ChangeExtension($audit.auditPath,'.result.json')
            WriteJson $summaryPath $summary
            $summary|ConvertTo-Json -Depth 15
            return
        }
    }
    throw 'REVIEW_MAX_ATTEMPTS_REQUIRES_INSPECTION'
}catch{
    $summary.status='failed';$summary.passed=$false;$summary['failure']=$_.Exception.Message
    WriteJson $summaryPath $summary
    throw
}
