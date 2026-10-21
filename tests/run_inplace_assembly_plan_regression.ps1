#Requires -Version 7.0
$ErrorActionPreference='Stop'
$entry=Join-Path $PSScriptRoot '../2-导入_InDesign/Invoke-JournalArticleAssembly.ps1'
$root=Join-Path ([IO.Path]::GetTempPath()) ('journal-inplace-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try{
 $document=Join-Path $root 'fixture_QA.indd'
 [IO.File]::WriteAllText($document,'QA fixture')
 $hash=(Get-FileHash $document -Algorithm SHA256).Hash
 $job=@{schemaVersion=1;taskId='fixture';templatePath=$document;outputPath=$document;inputs=@();formulas=@{mode='legacy-pdf'};panels=@();inPlace=$true;initialOutputSha256=$hash;articlePageRange=@(204,209)}
 $config=Join-Path $root 'job.json'
 [IO.File]::WriteAllText($config,($job|ConvertTo-Json -Depth 10))
 $answer= & $entry -ConfigPath $config -PlanOnly|Out-String|ConvertFrom-Json
 if($answer.status -ne 'ready-for-assembly' -or -not $answer.inPlace){throw 'VALID_INPLACE_PLAN_REJECTED'}
 $job.initialOutputSha256='0'*64
 [IO.File]::WriteAllText($config,($job|ConvertTo-Json -Depth 10))
 $rejected=$false
 try{& $entry -ConfigPath $config -PlanOnly|Out-Null}catch{if($_.Exception.Message -match 'INPLACE_OUTPUT_CHANGED'){$rejected=$true}else{throw}}
 if(-not $rejected){throw 'CHANGED_INPLACE_OUTPUT_ACCEPTED'}
 $job.initialOutputSha256=$hash;$job.inPlace=$false
 [IO.File]::WriteAllText($config,($job|ConvertTo-Json -Depth 10))
 $rejected=$false
 try{& $entry -ConfigPath $config -PlanOnly|Out-Null}catch{if($_.Exception.Message -match 'SOURCE_OUTPUT_COLLISION'){$rejected=$true}else{throw}}
 if(-not $rejected){throw 'LEGACY_COLLISION_PROTECTION_LOST'}
 Write-Output 'PASS explicit in-place identity plan, changed-output rejection and legacy collision protection'
 }finally{
 $resolved=[IO.Path]::GetFullPath($root)
 if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'journal-inplace-*'){throw 'UNSAFE_FIXTURE_CLEANUP'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
