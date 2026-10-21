param(
    [Parameter(Mandatory=$true)][string]$ConfigPath,
    [string]$QueueDirectory,
    [string]$LeaseId,
    [switch]$PlanOnly,
    [switch]$Resume,
    [ValidateSet('Assemble','NormalizeExisting','ReflowExisting','LayoutExisting','ApplyBottomExisting')][string]$Stage='Assemble'
)
Import-Module (Join-Path $PSScriptRoot 'JournalInDesignScript.psm1') -Force
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$job=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
if($job.schemaVersion -ne 1){throw 'ASSEMBLY_CONFIG_VERSION'}
if([IO.Path]::GetFileName($job.outputPath) -notmatch '(?i)QA|copy|副本'){throw 'ASSEMBLY_QA_REQUIRED'}
$inPlace=[bool]($job.PSObject.Properties['inPlace'] -and $job.inPlace -eq $true)
if(-not $inPlace -and [IO.Path]::GetFullPath($job.outputPath) -eq [IO.Path]::GetFullPath($job.templatePath)){throw 'SOURCE_OUTPUT_COLLISION'}
if($inPlace -and $Stage -eq 'Assemble'){
    if(-not(Test-Path -LiteralPath $job.outputPath -PathType Leaf)){throw 'INPLACE_OUTPUT_MISSING'}
    if(-not $job.PSObject.Properties['initialOutputSha256'] -or $job.initialOutputSha256 -notmatch '^[0-9a-fA-F]{64}$'){throw 'INPLACE_OUTPUT_IDENTITY_REQUIRED'}
    if((Get-FileHash -LiteralPath $job.outputPath -Algorithm SHA256).Hash -ine $job.initialOutputSha256){throw 'INPLACE_OUTPUT_CHANGED'}
    if(-not $job.PSObject.Properties['articlePageRange'] -or @($job.articlePageRange).Count -ne 2 -or $job.articlePageRange[0] -lt 0 -or $job.articlePageRange[1] -lt $job.articlePageRange[0]){throw 'INPLACE_ARTICLE_RANGE_REQUIRED'}
}
$fingerprints=@()
foreach($entry in $job.inputs){
    if(-not(Test-Path -LiteralPath $entry.path -PathType Leaf)){throw "INPUT_MISSING $($entry.name)"}
    $hash=(Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash
    if($hash -ne $entry.sha256){throw "INPUT_CHANGED $($entry.name)"}
    $fingerprints+=@{name=$entry.name;path=$entry.path;sha256=$hash}
}
if($job.formulas.mode -eq 'native-idms'){
    $seenNumbers=@{}
    if(-not $job.formulas.PSObject.Properties['entries']){throw 'FORMULA_IDMS_ENTRIES_REQUIRED'}
    foreach($formulaEntry in $job.formulas.entries){
        foreach($field in @('number','path','sha256','widthMm','heightMm','basePointSize')){
            if(-not $formulaEntry.PSObject.Properties[$field]){throw "FORMULA_IDMS_FIELD_REQUIRED $field"}
        }
        $number=[int]$formulaEntry.number
        if($number -lt 1 -or $number -ne [double]$formulaEntry.number -or $seenNumbers.ContainsKey($number)){throw 'FORMULA_IDMS_NUMBER'}
        $seenNumbers[$number]=$true
        if([IO.Path]::GetExtension($formulaEntry.path) -ne '.idms'){throw "FORMULA_IDMS_EXTENSION $number"}
        if(-not [IO.Path]::IsPathRooted($formulaEntry.path) -or -not(Test-Path -LiteralPath $formulaEntry.path -PathType Leaf)){throw "FORMULA_IDMS_MISSING $number"}
        if($formulaEntry.sha256 -notmatch '^[0-9a-fA-F]{64}$'){throw "FORMULA_IDMS_HASH_REQUIRED $number"}
        if([double]$formulaEntry.basePointSize -ne 10.5){throw "FORMULA_IDMS_BASE_SIZE $number"}
        foreach($field in @('widthMm','heightMm')){
            $dimension=[double]$formulaEntry.$field
            if([double]::IsNaN($dimension) -or [double]::IsInfinity($dimension) -or $dimension -le 0){throw "FORMULA_IDMS_DIMENSION $number/$field"}
        }
        $hash=(Get-FileHash -LiteralPath $formulaEntry.path -Algorithm SHA256).Hash
        if($hash -ne $formulaEntry.sha256){throw "FORMULA_IDMS_CHANGED $number"}
        $fingerprints+=@{name="native-formula-$number";path=$formulaEntry.path;sha256=$hash}
    }
}
function Save-ResolvedAssemblyPanels($Job,$Result,[string]$CurrentStage,[string]$Path){
    if($CurrentStage -ne 'Assemble' -or $Result.status -ne 'assembled-unchecked'){return}
    if(-not $Result.PSObject.Properties['panels'] -or -not @($Job.panels).Count){return}
    $updates=@()
    foreach($resolved in $Result.panels){
        if(-not $resolved.PSObject.Properties['numbers']){continue}
        if(-not $resolved.PSObject.Properties['pageTop'] -or $resolved.pageTop -isnot [bool]){throw 'ASSEMBLY_PANEL_RESOLUTION_INVALID'}
        $key=(@($resolved.numbers|Sort-Object) -join ',')
        $matches=@($Job.panels|Where-Object{(@($_.numbers|Sort-Object) -join ',') -eq $key})
        if($matches.Count -ne 1 -or @($updates|Where-Object{$_.key -eq $key}).Count){throw "ASSEMBLY_PANEL_RESOLUTION_IDENTITY $key"}
        $updates+=@{key=$key;panel=$matches[0];pageTop=$resolved.pageTop}
    }
    $changed=$false
    foreach($update in $updates){
        if(-not $update.panel.PSObject.Properties['pageTop'] -or $update.panel.pageTop -ne $update.pageTop){
            if($update.panel.PSObject.Properties['pageTop']){$update.panel.pageTop=$update.pageTop}
            else{$update.panel|Add-Member -NotePropertyName pageTop -NotePropertyValue $update.pageTop}
            $changed=$true
        }
    }
    if($changed){
        $temporary=$Path+'.resolved-panels.tmp'
        [IO.File]::WriteAllText($temporary,($Job|ConvertTo-Json -Depth 80),[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    }
}
function Write-AssemblyState($Value){
    $temporary=$job.statePath+'.tmp'
    [IO.File]::WriteAllText($temporary,($Value|ConvertTo-Json -Depth 80),[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $job.statePath -Force
    if($job.PSObject.Properties['workflowStatePath']){
        $workflow=Get-Content -LiteralPath $job.workflowStatePath -Raw -Encoding UTF8|ConvertFrom-Json
        $matches=@($workflow.results.PSObject.Properties.Value|Where-Object{
            [IO.Path]::GetFullPath($_.documentPath) -eq [IO.Path]::GetFullPath($job.outputPath)
        })
        if($matches.Count -ne 1){throw 'WORKFLOW_DOCUMENT_IDENTITY'}
        $article=$matches[0]
        $article|Add-Member -NotePropertyName currentAuditPending -NotePropertyValue $true -Force
        $article|Add-Member -NotePropertyName activeStepStatePath -NotePropertyValue $job.statePath -Force
        $article.passed=$false
        if($Value.outputSha256){$article.documentSha256=$Value.outputSha256}
        if($Value.status -in @('assembled-unchecked','normalized-unchecked','reflowed-unchecked','bottom-applied-unchecked','layout-applied-unchecked')){
            $article|Add-Member -NotePropertyName lastSuccess -NotePropertyValue $job.configVersion -Force
        }
        $workflow.currentArticle=$article.article
        $workflow.currentStage=$Stage
        $workflow.status=$Value.status
        $workflow.activeStepStatePath=$job.statePath
        $workflow.nextAction=$Value.nextAction
        $workflow.updatedAt=[DateTime]::UtcNow.ToString('o')
        $pending=$job.workflowStatePath+'.tmp'
        [IO.File]::WriteAllText($pending,($workflow|ConvertTo-Json -Depth 90),[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $pending -Destination $job.workflowStatePath -Force
    }
}
if($Resume){
    $saved=Get-Content -LiteralPath $job.statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if($saved.configVersion -ne $job.configVersion){throw 'CHECKPOINT_CONFIG_CHANGED'}
    if($saved.outputSha256 -and (Get-FileHash -LiteralPath $job.outputPath -Algorithm SHA256).Hash -ne $saved.outputSha256){throw 'CHECKPOINT_OUTPUT_CHANGED'}
    $saved | ConvertTo-Json -Depth 80
    return
}
if($PlanOnly){
    @{taskId=$job.taskId;inputsVerified=$fingerprints.Count;panels=$job.panels.Count;outputPath=$job.outputPath;inPlace=$inPlace;status='ready-for-assembly'}|ConvertTo-Json -Depth 10
    return
}
if(-not $QueueDirectory -or -not $LeaseId){throw 'INDESIGN_LEASE_REQUIRED'}
$lease=Get-Content -LiteralPath (Join-Path $QueueDirectory 'locks/indesign.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($lease.leaseId -ne $LeaseId){throw 'INDESIGN_LEASE_MISMATCH'}
if($Stage -eq 'Assemble' -and -not $inPlace -and (Test-Path -LiteralPath $job.outputPath)){throw 'OUTPUT_EXISTS_USE_CHECKPOINT'}
if($Stage -ne 'Assemble'){
    if(-not $job.continuation.documentId -or -not $job.continuation.outputSha256){throw 'CONTINUATION_IDENTITY_REQUIRED'}
    if((Get-FileHash -LiteralPath $job.outputPath -Algorithm SHA256).Hash -ne $job.continuation.outputSha256){throw 'CONTINUATION_OUTPUT_CHANGED'}
}
$process=Get-Process InDesign -ErrorAction Stop | Select-Object -First 1
if(-not $process.Responding -or $process.MainWindowTitle -match '^(Script Alert|脚本警告|警告)'){throw 'INDESIGN_BLOCKED'}
if($Stage -eq 'Assemble' -and -not $inPlace){Copy-Item -LiteralPath $job.templatePath -Destination $job.outputPath}
$state=@{schemaVersion=1;configVersion=$job.configVersion;taskId=$job.taskId;inputs=$fingerprints;outputPath=$job.outputPath;outputSha256=$null;status='running';stage='assembly';nextAction='inspect-assembly-result';updatedAt=[DateTime]::UtcNow.ToString('o')}
Write-AssemblyState $state
$modules=@('journal_document_session.jsxinc','journal_frontmatter.jsxinc','journal_layout_rules.jsxinc','journal_regression_snapshot.jsxinc','journal_layout_measurement.jsxinc','journal_reflow.jsxinc','journal_bottom_plan.jsxinc','journal_layout_profile.jsxinc','journal_article_assembly.jsxinc')
$jsx=($modules|ForEach-Object{[IO.File]::ReadAllText((Join-Path $PSScriptRoot $_),[Text.Encoding]::UTF8)}) -join "`n"
$config=$job|ConvertTo-Json -Depth 80 -Compress
$entryMethod=switch($Stage){'Assemble'{'run'}'NormalizeExisting'{'normalizeExisting'}'ReflowExisting'{'reflowExisting'}'LayoutExisting'{'layoutExisting'}'ApplyBottomExisting'{'applyBottomExisting'}}
$jsx+="`nvar assemblyAnswer;try{assemblyAnswer=JournalArticleAssembly.$entryMethod(app,$config);}catch(assemblyError){assemblyAnswer={status:'failed',failure:String(assemblyError),line:assemblyError.line};}JournalRegressionSnapshot.json(assemblyAnswer);"
$watch=[Diagnostics.Stopwatch]::StartNew()
try{
    $app=New-Object -ComObject 'InDesign.Application.2020'
    $raw=[string](Invoke-JournalInDesignScript -Application $app -Code ($jsx))
    $result=$raw|ConvertFrom-Json
    Save-ResolvedAssemblyPanels $job $result $Stage $ConfigPath
    $state.result=$result
    $state.status=$result.status
    $state.stage=if($Stage -eq 'Assemble' -and $result.PSObject.Properties['phases'] -and $result.phases.Count){$result.phases[-1].name}else{$Stage}
    $state.nextAction=if($result.status -in @('assembled-unchecked','normalized-unchecked','reflowed-unchecked','bottom-applied-unchecked','layout-applied-unchecked')){'run-structural-and-format-gates'}else{'repair-shared-cause-preserve-candidate'}
    [IO.File]::WriteAllText($job.resultPath,($result|ConvertTo-Json -Depth 80),[Text.UTF8Encoding]::new($false))
}catch{
    $state.status='call-failed'
    $state.failure=$_.Exception.Message
    $state.nextAction='inspect-current-document-and-result-before-any-retry'
    throw
}finally{
    $watch.Stop()
    $state.elapsedMs=$watch.ElapsedMilliseconds
    $state.updatedAt=[DateTime]::UtcNow.ToString('o')
    $state.outputSha256=(Get-FileHash -LiteralPath $job.outputPath -Algorithm SHA256).Hash
    Write-AssemblyState $state
}
if($result.status -eq 'failed'){throw "ASSEMBLY_FAILED $($result.failure) at $($result.line)"}
$result | ConvertTo-Json -Depth 80
