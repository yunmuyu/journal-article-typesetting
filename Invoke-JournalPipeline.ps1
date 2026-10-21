#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$SpecPath,[switch]$PlanOnly)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function ReadJson([string]$Path){Get-Content -LiteralPath $Path -Raw -Encoding utf8|ConvertFrom-Json -AsHashtable}
function FileHash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function TextHash([string]$Value){[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Value))).ToLowerInvariant()}
function WriteState {
    $parent=Split-Path -Parent $script:statePath
    [void][IO.Directory]::CreateDirectory($parent)
    $temporary=$script:statePath+'.tmp-'+[guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($temporary,($script:state|ConvertTo-Json -Depth 70),[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $script:statePath -Force
}
function JsonProperty([string]$Path,[string]$Property){
    $value=ReadJson $Path
    foreach($part in $Property.Split('.')){if($value -isnot [Collections.IDictionary] -or -not $value.Contains($part)){throw "JSON_PROPERTY_MISSING $Path $Property"};$value=$value[$part]}
    return ,$value
}
function CheckAssertions($Stage){
    if(-not $Stage.Contains('assertions')){return}
    foreach($assertion in $Stage.assertions){
        $actual=JsonProperty $assertion.path $assertion.property
        if(($actual|ConvertTo-Json -Compress -Depth 20) -cne ($assertion.expected|ConvertTo-Json -Compress -Depth 20)){throw "STAGE_ASSERTION_FAILED $($Stage.id) $($assertion.property)"}
    }
}
$state=$null;$activeStage=$null
try {
    $specFile=(Get-Item -LiteralPath $SpecPath).FullName
    $spec=ReadJson $specFile
    if($spec.schemaVersion -ne 1 -or -not $spec.stages.Count){throw 'PIPELINE_SPEC_INVALID'}
    $seen=@{}
    foreach($stage in $spec.stages){
        if($stage.id -notmatch '^[a-z0-9][a-z0-9-]*$' -or $seen.ContainsKey($stage.id)){throw 'STAGE_ID_INVALID'}
        foreach($dependency in $stage.dependsOn){if(-not $seen.ContainsKey($dependency)){throw "DEPENDENCY_ORDER $dependency"}}
        $seen[$stage.id]=$true
        foreach($property in @('executable','arguments','inputFiles','outputs')){if(-not $stage.Contains($property)){throw "STAGE_FIELD_MISSING $($stage.id) $property"}}
        foreach($path in @($stage.inputFiles)+@($stage.outputs)){if(-not [IO.Path]::IsPathRooted($path)){throw "ABSOLUTE_PATH_REQUIRED $path"}}
    }
    if($PlanOnly){@{status='plan-only';stages=@($spec.stages|ForEach-Object{@{id=$_.id;executable=$_.executable;outputs=$_.outputs}})}|ConvertTo-Json -Depth 20;exit 0}
    $statePath=[IO.Path]::GetFullPath($spec.statePath)
    $pipelineId=TextHash $specFile.ToLowerInvariant()
    $loaded=if(Test-Path -LiteralPath $statePath){ReadJson $statePath}else{@{schemaVersion=1;pipelineId=$pipelineId;startedAt=[DateTime]::UtcNow.ToString('o');stages=@{};artifacts=@{};runs=@()}}
    if($loaded -isnot [Collections.IDictionary] -or -not $loaded.Contains('pipelineId') -or $loaded.schemaVersion -ne 1 -or $loaded.pipelineId -cne $pipelineId){throw 'CHECKPOINT_IDENTITY_MISMATCH'}
    $state=$loaded
    $run=@{startedAt=[DateTime]::UtcNow.ToString('o');executed=@();reused=@();status='running'}
    $state.runs+=@($run);$state.status='running';WriteState
    foreach($path in @($state.artifacts.Keys)){
        $artifact=$state.artifacts[$path]
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "CHECKPOINT_OUTPUT_MISSING $path"}
        if((FileHash $path) -cne $artifact.sha256){throw "CHECKPOINT_OUTPUT_CHANGED $path"}
    }

    foreach($stage in $spec.stages){
        $activeStage=$stage.id
        $identity=[ordered]@{recipe=$stage;inputs=[ordered]@{};dependencies=[ordered]@{}}
        foreach($path in $stage.inputFiles){$identity.inputs[$path]=FileHash $path}
        foreach($dependency in $stage.dependsOn){
            if($state.stages[$dependency].status -ne 'passed'){throw "DEPENDENCY_NOT_PASSED $dependency"}
            $identity.dependencies[$dependency]=$state.stages[$dependency].key
        }
        $key=TextHash ($identity|ConvertTo-Json -Depth 60 -Compress)
        $old=if($state.stages.ContainsKey($activeStage)){$state.stages[$activeStage]}else{$null}
        if($old -and $old.status -eq 'passed' -and $old.key -ceq $key){
            CheckAssertions $stage
            $run.reused+=@($activeStage);Write-Output "REUSED $activeStage";continue
        }
        $attempt=if($old){[int]$old.attempt+1}else{1}
        $record=@{status='running';key=$key;attempt=$attempt;startedAt=[DateTime]::UtcNow.ToString('o')}
        $state.stages[$activeStage]=$record;WriteState
        $arguments=@($stage.arguments|ForEach-Object{if($_ -is [Collections.IDictionary]){[string](JsonProperty $_.jsonFile $_.property)}else{[string]$_}})
        $info=[Diagnostics.ProcessStartInfo]::new([string]$stage.executable)
        $info.UseShellExecute=$false;$info.CreateNoWindow=$true
        $info.WorkingDirectory=$spec.workingDirectory
        $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        $info.StandardOutputEncoding=[Text.UTF8Encoding]::new($false);$info.StandardErrorEncoding=[Text.UTF8Encoding]::new($false)
        foreach($argument in $arguments){$info.ArgumentList.Add($argument)}
        $process=[Diagnostics.Process]::new();$process.StartInfo=$info
        $timer=[Diagnostics.Stopwatch]::StartNew();[void]$process.Start()
        $record.processId=$process.Id;WriteState
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        $process.WaitForExit();$timer.Stop()
        $logDirectory=Join-Path (Split-Path -Parent $statePath) 'pipeline-logs';[void][IO.Directory]::CreateDirectory($logDirectory)
        $record.stdout=Join-Path $logDirectory "$activeStage.$attempt.stdout.log"
        $record.stderr=Join-Path $logDirectory "$activeStage.$attempt.stderr.log"
        [IO.File]::WriteAllText($record.stdout,$stdout.GetAwaiter().GetResult(),[Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($record.stderr,$stderr.GetAwaiter().GetResult(),[Text.UTF8Encoding]::new($false))
        $record.elapsedMs=$timer.ElapsedMilliseconds;$record.exitCode=$process.ExitCode
        if($process.ExitCode -ne 0){throw "STAGE_PROCESS_FAILED $activeStage $($process.ExitCode)"}
        foreach($path in $stage.outputs){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "STAGE_OUTPUT_MISSING $activeStage $path"}}
        CheckAssertions $stage
        foreach($path in $stage.outputs){$state.artifacts[$path]=@{sha256=(FileHash $path);lastWriter=$activeStage}}
        $record.status='passed';$record.finishedAt=[DateTime]::UtcNow.ToString('o');$run.executed+=@($activeStage);WriteState
        Write-Output "PASSED $activeStage $($record.elapsedMs)ms"
        $process.Dispose()
    }
    $run.status='passed';$run.finishedAt=[DateTime]::UtcNow.ToString('o');$state.status='pipeline-passed';$state.activeStage=$null;WriteState
    @{status=$state.status;statePath=$statePath;executed=$run.executed;reused=$run.reused}|ConvertTo-Json -Depth 10
} catch {
    if($null -ne $state){
        $state.status='failed';$state.failure=$_.Exception.Message;$state.activeStage=$activeStage
        if($activeStage -and $state.stages.ContainsKey($activeStage)){$state.stages[$activeStage].status='failed'}
        if($state.runs.Count){$state.runs[-1].status='failed';$state.runs[-1].finishedAt=[DateTime]::UtcNow.ToString('o')}
        WriteState
    }
    Write-Error $_.Exception.Message -ErrorAction Continue
    exit 1
}
