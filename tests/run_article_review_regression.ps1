param([Parameter(Mandatory=$true)][string]$WorkingDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Join-Path ([IO.Path]::GetFullPath($WorkingDirectory)) ('article-review-regression-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $root 'queue/locks') -Force|Out-Null
$entry=Join-Path (Split-Path $PSScriptRoot) '2-导入_InDesign/Invoke-JournalArticleReview.ps1'
function WriteTestJson([string]$Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))}
function ExpectFailure([string]$Code,[scriptblock]$Action){
    $caught=$false
    try{& $Action|Out-Null}catch{if($_.Exception.Message -notlike "*$Code*"){throw};$caught=$true}
    if(-not $caught){throw "EXPECTED_FAILURE $Code"}
}
$output=Join-Path $root 'article_QA.indd';$template=Join-Path $root 'template.indd';$source=Join-Path $root 'source.json'
[IO.File]::WriteAllText($output,'synthetic QA only');[IO.File]::WriteAllText($template,'synthetic template');[IO.File]::WriteAllText($source,'source')
$auditPath=Join-Path $root 'audit.json';$resultPath=Join-Path $root 'assembly.result.json';$jobPath=Join-Path $root 'job.json'
$leasePath=Join-Path $root 'queue/locks/indesign.json'
$lease=[ordered]@{leaseId='synthetic-lease';taskId='synthetic-task';lane='InDesign'}
WriteTestJson $leasePath $lease
$audit=[ordered]@{documentPath=$output;configVersion='test';templateContractVersion='test-contract';bindings=@()}
WriteTestJson $auditPath $audit
$assembly=[ordered]@{documentId=123;outputPath=$output;status='assembled-unchecked';bindings=@(@{id=1;role='body'})}
WriteTestJson $resultPath $assembly
$job=[ordered]@{schemaVersion=1;taskId='synthetic-task';outputPath=$output;templatePath=$template;auditConfigPath=$auditPath;resultPath=$resultPath;inputs=@(@{name='source';path=$source;sha256=(Get-FileHash $source -Algorithm SHA256).Hash})}
WriteTestJson $jobPath $job
$arguments=@{ConfigPath=$jobPath;QueueDirectory=(Join-Path $root 'queue');LeaseId='synthetic-lease';PlanOnly=$true}
$before=(Get-FileHash $jobPath -Algorithm SHA256).Hash
$plan=(& $entry @arguments)|ConvertFrom-Json
if($plan.status -ne 'planned' -or -not $plan.needsBindings -or $plan.adobeCalled -ne $false -or $plan.documentId -ne 123){throw 'REVIEW_PLAN_CONTRACT'}
if((Get-FileHash $jobPath -Algorithm SHA256).Hash -cne $before){throw 'PLAN_ONLY_CHANGED_JOB'}
$job.continuation=@{documentId=456;outputSha256=(Get-FileHash $output -Algorithm SHA256).Hash}
WriteTestJson $jobPath $job
$plan=(& $entry @arguments)|ConvertFrom-Json
if($plan.documentId -ne 456){throw 'CONTINUATION_PRIORITY'}
$arguments.LeaseId='wrong'
ExpectFailure 'REVIEW_INDESIGN_LEASE_MISMATCH' {& $entry @arguments}
$arguments.LeaseId='synthetic-lease'
[IO.File]::WriteAllText($source,'changed')
ExpectFailure 'REVIEW_IMMUTABLE_INPUT_CHANGED' {& $entry @arguments}
[IO.File]::WriteAllText($source,'source')
$job.continuation.outputSha256='0'*64;WriteTestJson $jobPath $job
ExpectFailure 'REVIEW_CONTINUATION_OUTPUT_CHANGED' {& $entry @arguments}
$job.Remove('continuation');WriteTestJson $jobPath $job
$assembly.outputPath=Join-Path $root 'other_QA.indd';WriteTestJson $resultPath $assembly
ExpectFailure 'REVIEW_ASSEMBLY_DOCUMENT_MISMATCH' {& $entry @arguments}
$text=[IO.File]::ReadAllText($entry)
if($text.IndexOf('if($PlanOnly)') -ge $text.IndexOf("New-Object -ComObject")){throw 'PLAN_ONLY_MUST_PRECEDE_ADOBE'}
if($text -match '-Action\s+(Pass|Advance|Complete)'){throw 'REVIEW_MUST_NOT_ADVANCE_HUMAN_WORKFLOW'}
if($text -notmatch 'if\(-not \$check.passed\)' -or $text -notmatch 'REVIEW_MAX_ATTEMPTS_REQUIRES_INSPECTION'){throw 'FAILURE_MUST_NOT_PASS'}
[ordered]@{passed=$true;checks=9;adobeCalled=$false;fixtureDirectory=$root}|ConvertTo-Json
