param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
Import-Module (Join-Path $ProjectRoot '2-导入_InDesign/JournalPreflight.psm1') -Force
$root=Join-Path ([IO.Path]::GetTempPath()) ('journal-table-formula-'+[guid]::NewGuid().ToString('N'))
function Write-FixtureJson($Value,[string]$Path){
    [IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
}
try {
    New-Item -ItemType Directory -Path $root|Out-Null
    $figures=Join-Path $root 'figures'
    New-Item -ItemType Directory -Path $figures|Out-Null
    $source=Join-Path $root 'source.docx'
    [IO.File]::WriteAllText($source,'synthetic input; no Adobe execution')
    $articlePath=Join-Path $root 'article.json'
    $tablePath=Join-Path $root 'tables.json'
    $manifestPath=Join-Path $root 'formulas.json'
    $article=@{blocks=@(@{role='body';text='Inline ⟦EQ-001⟧'})}
    $tables=ConvertFrom-Json '{"tables":[{"rows":[["Input ⟦EQ-002⟧"],["Output ⟦EQ-003⟧"]],"cellParagraphs":[[[{"text":"Input ⟦EQ-002⟧"}]],[[{"text":"Output ⟦EQ-003⟧"}]]]}]}'
    Write-FixtureJson $article $articlePath
    Write-FixtureJson $tables $tablePath
    Write-FixtureJson @{formula_count=3} $manifestPath
    $task=[pscustomobject]@{taskId='table-formula-fixture';author='fixture';sourceWord=$source;articleJson=$articlePath;figureDirectory=$figures;outputDirectory=$root;tableJson=$tablePath;formulaManifest=$manifestPath}
    $plan=New-JournalPreflightPlan $task
    if($plan.counts.formulas -ne 3 -or $plan.status -ne 'ready'){throw "BODY_PLUS_TABLE_COUNT: expected 3/ready, got $($plan.counts.formulas)/$($plan.status)"}
    $article.blocks[0].text='No formula in the body'
    Write-FixtureJson $article $articlePath
    Write-FixtureJson @{formula_count=2} $manifestPath
    $plan=New-JournalPreflightPlan $task
    if($plan.counts.formulas -ne 2 -or $plan.status -ne 'ready'){throw 'TABLE_ONLY_FORMULAS_NOT_COUNTED'}
    Write-FixtureJson @{formula_count=1} $manifestPath
    $plan=New-JournalPreflightPlan $task
    if(@($plan.issues.code) -notcontains 'FORMULA_COUNT'){throw 'TABLE_FORMULA_MANIFEST_MISMATCH_NOT_BLOCKED'}
    $task.formulaManifest=Join-Path $root 'missing.json'
    $plan=New-JournalPreflightPlan $task
    if(@($plan.issues.code) -notcontains 'FORMULA_MANIFEST'){throw 'TABLE_ONLY_MISSING_MANIFEST_NOT_BLOCKED'}
    $task.PSObject.Properties.Remove('tableJson')
    $task.PSObject.Properties.Remove('formulaManifest')
    $article.blocks=@(@{role='math';text='legacy equation'})
    Write-FixtureJson $article $articlePath
    $plan=New-JournalPreflightPlan $task
    if($plan.counts.formulas -ne 1 -or @($plan.issues.code) -notcontains 'FORMULA_MANIFEST'){throw 'LEGACY_MATH_FALLBACK_CHANGED'}
    Write-Output 'PASS body/table formula counts, mirrored text deduplication, missing/mismatched manifests and legacy math fallback'
} finally {
    $absolute=[IO.Path]::GetFullPath($root)
    $boundary=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if(!$absolute.StartsWith($boundary,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($absolute) -notlike 'journal-table-formula-*'){throw 'TEST_CLEANUP_PATH'}
    if(Test-Path -LiteralPath $absolute){Remove-Item -LiteralPath $absolute -Recurse -Force}
}
