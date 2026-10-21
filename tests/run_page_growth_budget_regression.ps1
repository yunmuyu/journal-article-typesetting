$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$entry=Join-Path (Split-Path $PSScriptRoot) '2-导入_InDesign/Invoke-JournalArticleReview.ps1'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../work'))
$testRoot=Join-Path $root ('page-growth-budget-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $testRoot 'queue/locks') -Force|Out-Null
function WriteTestJson($Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))}
try{
    $document=Join-Path $testRoot 'article_QA.indd';$template=Join-Path $testRoot 'template.indd';$source=Join-Path $testRoot 'source.json'
    foreach($path in @($document,$template,$source)){[IO.File]::WriteAllText($path,'synthetic only')}
    $auditPath=Join-Path $testRoot 'audit.json';$resultPath=Join-Path $testRoot 'assembly.result.json';$jobPath=Join-Path $testRoot 'job.json'
    WriteTestJson (Join-Path $testRoot 'queue/locks/indesign.json') @{leaseId='lease';taskId='task';lane='InDesign'}
    $audit=@{documentPath=$document;configVersion='test';templateContractVersion='test';pageBudget=8;bindings=@(@{id=1;role='front'},@{id=2;role='body'},@{id=3;role='footer'},@{id=4;role='doi'})}
    WriteTestJson $auditPath $audit
    $assembly=@{status='normalized-unchecked';documentId=28;outputPath=$document;pages=10;addedPages=2;bindings=@($audit.bindings)}
    WriteTestJson $resultPath $assembly
    $job=@{schemaVersion=1;taskId='task';allowPageGrowth=$true;expected=@{pages=8};outputPath=$document;templatePath=$template;auditConfigPath=$auditPath;resultPath=$resultPath;continuation=@{documentId=28;outputSha256=(Get-FileHash $document).Hash};inputs=@(@{name='source';path=$source;sha256=(Get-FileHash $source).Hash})}
    WriteTestJson $jobPath $job
    $arguments=@{ConfigPath=$jobPath;QueueDirectory=(Join-Path $testRoot 'queue');LeaseId='lease';PlanOnly=$true}
    $originalJobHash=(Get-FileHash $jobPath).Hash;$originalAuditHash=(Get-FileHash $auditPath).Hash
    $plan=(& $entry @arguments)|ConvertFrom-Json
    if($plan.needsBindings -or $plan.pageBudgetResolution.allocatedPages -ne 8 -or $plan.pageBudgetResolution.measuredPages -ne 10){throw 'PREBOUND_AUDIT_GROWTH_NOT_RESOLVED'}
    if((Get-FileHash $jobPath).Hash -ne $originalJobHash -or (Get-FileHash $auditPath).Hash -ne $originalAuditHash){throw 'PLAN_ONLY_WROTE_ORIGINAL'}
    $job.Remove('allowPageGrowth');WriteTestJson $jobPath $job
    $plan=(& $entry @arguments)|ConvertFrom-Json
    if($null -ne $plan.pageBudgetResolution){throw 'LEGACY_PAGE_BUDGET_OVERRIDDEN'}
    $job.allowPageGrowth=$true;WriteTestJson $jobPath $job
    $assembly.documentId=99;WriteTestJson $resultPath $assembly
    $failed=$false;try{& $entry @arguments|Out-Null}catch{if($_.Exception.Message -notmatch 'REVIEW_PAGE_GROWTH_IDENTITY'){throw};$failed=$true};if(-not $failed){throw 'MISMATCHED_ASSEMBLY_ACCEPTED'}
    $assembly.documentId=28;$assembly.pages=0;WriteTestJson $resultPath $assembly
    $failed=$false;try{& $entry @arguments|Out-Null}catch{if($_.Exception.Message -notmatch 'REVIEW_PAGE_GROWTH_RESULT_REQUIRED'){throw};$failed=$true};if(-not $failed){throw 'BAD_MEASURED_PAGES_ACCEPTED'}
    $text=[IO.File]::ReadAllText($entry)
    if($text.IndexOf('$pageBudgetResolution=Resolve-PageGrowthBudget') -gt $text.IndexOf('$needsBindings=@')){throw 'BUDGET_DEPENDS_ON_BINDINGS'}
    if(-not $text.Contains("'page-growth.audit.json'") -or $text.IndexOf('if($pageBudgetResolution){') -lt $text.IndexOf('PersistContinuation') -or -not $text.Contains('$summary[''pageBudgetResolution'']=$pageBudgetResolution')){throw 'DERIVED_AUDIT_OR_PROVENANCE_MISSING'}
    if((Get-FileHash $auditPath).Hash -ne $originalAuditHash){throw 'ORIGINAL_AUDIT_CHANGED'}
    Write-Output 'PASS explicit page-growth budget from matching actual assembly pages, prebound audit independence, original budget provenance and legacy strictness; no Adobe called'
}finally{
    $resolved=[IO.Path]::GetFullPath($testRoot)
    if(-not $resolved.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'page-growth-budget-*'){throw 'TEST_CLEANUP_PATH'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
