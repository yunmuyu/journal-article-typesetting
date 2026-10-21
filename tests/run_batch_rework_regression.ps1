param()
$ErrorActionPreference='Stop'
$entry=Join-Path (Split-Path $PSScriptRoot) '2-导入_InDesign/Invoke-JournalBatch.ps1'
$queue=Join-Path ([IO.Path]::GetTempPath()) ('journal-rework-'+[guid]::NewGuid().ToString('N'))
try{
 [void](New-Item -ItemType Directory -Path (Join-Path $queue 'tasks') -Force)
 [void](New-Item -ItemType Directory -Path (Join-Path $queue 'locks') -Force)
 $path=Join-Path $queue 'tasks/fixture.json'
 $record=@{updatedAt='synthetic';taskId='fixture';status='passed';formulaReady=$true;workflowStage='full-article-approved';evidencePath='old-pass';checkpointPath='old-checkpoint';checkpointSha256='old-hash';history=@()}
 [IO.File]::WriteAllText($path,($record|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
 $result=(& $entry -Action Rework -QueueDirectory $queue -TaskId fixture|Out-String)|ConvertFrom-Json
 if($result.status -ne 'ready' -or $result.workflowStage -ne 'formulas-approved' -or $result.evidencePath -or $result.checkpointPath){throw 'REWORK_OLD_PASS_REUSED'}
 if(@(Get-ChildItem (Join-Path $queue 'rework-history') -File).Count -ne 1){throw 'REWORK_BACKUP_MISSING'}
 $record.status='rereview';[IO.File]::WriteAllText($path,($record|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
 [IO.File]::WriteAllText((Join-Path $queue 'locks/indesign.json'),'\{"taskId":"fixture"\}'.Replace('\',''))
 $rejected=$false;try{& $entry -Action Rework -QueueDirectory $queue -TaskId fixture|Out-Null}catch{if($_ -match 'REWORK_ACTIVE_LEASE'){$rejected=$true}else{throw}}
 if(-not $rejected){throw 'REWORK_ACTIVE_TASK_ACCEPTED'}
 'PASS reversible rework, stale approval invalidation and active-lease guard'
}finally{if(Test-Path -LiteralPath $queue){$resolved=[IO.Path]::GetFullPath($queue);$prefix=Join-Path ([IO.Path]::GetTempPath()) 'journal-rework-';if(-not $resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'UNSAFE_FIXTURE_PATH'};Remove-Item -LiteralPath $resolved -Recurse -Force}}
