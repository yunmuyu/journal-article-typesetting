#Requires -Version 7.0
$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('journal-parallel-'+[guid]::NewGuid().ToString('N'))
$tools=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../2-导入_InDesign'))
$job=$null
try {
    [void][IO.Directory]::CreateDirectory((Join-Path $root 'tasks'))
    [void][IO.Directory]::CreateDirectory((Join-Path $root 'locks'))
    [void][IO.Directory]::CreateDirectory((Join-Path $root 'checkpoints'))
    $plan=Join-Path $root 'plan.json'
    [IO.File]::WriteAllText($plan,'{"counts":{"formulas":0}}')
    # Given: four separate ready articles contend for one InDesign writer.
    foreach($i in 1..4){
        @{taskId="article-$i";status='ready';workflowStage='formulas-approved';formulaReady=$true;planPath=$plan;updatedAt='2026-01-01T00:00:00Z'}|
            ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root "tasks/article-$i.json") -Encoding utf8
    }
    $gate=Join-Path $root 'start';$batch=Join-Path $tools 'Invoke-JournalBatch.ps1'
    $job=1..4|ForEach-Object -Parallel {
        $ErrorActionPreference='Stop'
        [IO.File]::WriteAllText((Join-Path $using:root "ready-$_"),'ready')
        $deadline=[DateTime]::UtcNow.AddSeconds(20)
        while(!(Test-Path -LiteralPath $using:gate)){if([DateTime]::UtcNow -gt $deadline){throw 'START_BARRIER_TIMEOUT'};Start-Sleep -Milliseconds 10}
        try{$lease=& $using:batch -Action Acquire -QueueDirectory $using:root -TaskId "article-$_" -Lane InDesign|ConvertFrom-Json;[pscustomobject]@{acquired=$true;lease=$lease}}
        catch{[pscustomobject]@{acquired=$false;error=$_.Exception.Message}}
    } -ThrottleLimit 4 -AsJob
    $deadline=[DateTime]::UtcNow.AddSeconds(20)
    while(@(Get-ChildItem -LiteralPath $root -Filter 'ready-*').Count -lt 4){if([DateTime]::UtcNow -gt $deadline){throw 'READY_BARRIER_TIMEOUT'};Start-Sleep -Milliseconds 10}
    # When: all four public queue requests start together.
    [IO.File]::WriteAllText($gate,'go')
    $results=@($job|Wait-Job -Timeout 30|Receive-Job -ErrorAction Stop)
    if($job.State -ne 'Completed'){throw "WORKER_STATE $($job.State)"}
    $winners=@($results|Where-Object acquired)
    # Then: one lease wins; losing articles remain ready.
    if($winners.Count -ne 1){throw "MULTIPLE_WRITERS: $($winners.Count) acquired one lane"}
    $states=@(Get-ChildItem -LiteralPath (Join-Path $root 'tasks') -Filter '*.json'|ForEach-Object{Get-Content -LiteralPath $_.FullName -Raw|ConvertFrom-Json})
    $layout=@($states|Where-Object status -EQ 'layout')
    if($layout.Count -ne 1 -or $layout[0].taskId -ne $winners[0].lease.taskId -or @($states|Where-Object status -EQ 'ready').Count -ne 3){throw 'LOSER_STATE_MUTATED'}
    if(@(Get-ChildItem -LiteralPath (Join-Path $root 'locks') -Filter '*.tmp').Count){throw 'LEASE_TEMP_FILE_LEFT_BEHIND'}
    # Given: another article needs Illustrator while InDesign is held.
    $formulaPlan=Join-Path $root 'formula-plan.json';[IO.File]::WriteAllText($formulaPlan,'{"counts":{"formulas":1}}')
    @{taskId='formula-article';status='ready';workflowStage='figures-approved';formulaReady=$false;planPath=$formulaPlan;updatedAt='2026-01-01T00:00:00Z'}|
        ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'tasks/formula-article.json') -Encoding utf8
    # When: acquire its separate software lane, without releasing InDesign.
    $formula=& $batch -Action Acquire -QueueDirectory $root -TaskId 'formula-article' -Lane Illustrator|ConvertFrom-Json
    # Then: different software lanes coexist and neither replaces the other.
    $held=Get-Content -LiteralPath (Join-Path $root 'locks/indesign.json') -Raw|ConvertFrom-Json
    if($held.leaseId -ne $winners[0].lease.leaseId -or !$formula.leaseId){throw 'CROSS_LANE_INTERFERENCE'}
    & $batch -Action Release -QueueDirectory $root -Lane Illustrator -LeaseId $formula.leaseId|Out-Null
    & $batch -Action Release -QueueDirectory $root -Lane InDesign -LeaseId $held.leaseId|Out-Null
    'PASS four concurrent requests: one writer, losers unchanged, Illustrator/InDesign lanes coexist'
} finally {
    if($job){$job|Stop-Job;$job|Remove-Job -Force}
    $resolved=[IO.Path]::GetFullPath($root)
    if(!$resolved.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){throw 'UNSAFE_TEMP_ROOT'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
