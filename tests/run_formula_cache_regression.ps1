param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$modulePath=Join-Path $ProjectRoot '2-导入_InDesign\JournalFormulaCache.psm1'
$nativePath=Join-Path $ProjectRoot '2-导入_InDesign\journal_formula_native_cache.jsx'
Import-Module $modulePath -Force
$root=Join-Path ([IO.Path]::GetTempPath()) ('journal-formula-cache-'+[guid]::NewGuid().ToString('N'))
try{
 New-Item -ItemType Directory -Path (Join-Path $root 'input') -Force|Out-Null
 $source=Join-Path $root 'input\formula-1.wmf';[IO.File]::WriteAllBytes($source,[byte[]](1,3,3,7));Copy-Item -LiteralPath $source -Destination (Join-Path $root 'input\formula-2.wmf')
 $cache=Join-Path $root 'cache';$rule=Get-JournalFormulaRule
 $first=Resolve-JournalFormulaCache -InputDirectory (Split-Path $source) -CacheRoot $cache -Numbers 1 -Rule $rule
 if($first.items[0].status -ne 'miss'){throw 'Fresh source was not a miss'}
 $item=$first.items[0];New-Item -ItemType Directory -Path $item.cacheDirectory -Force|Out-Null
 $artifacts=[ordered]@{}
 foreach($name in @('ai','pdf','png')){$path=Join-Path $item.cacheDirectory ('formula.'+$name);[IO.File]::WriteAllText($path,$name);$artifacts[$name]=[ordered]@{path=$path;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}}
 $record=[ordered]@{schemaVersion=1;cacheKey=$item.cacheKey;rule=$rule;source=[ordered]@{path=$source;sha256=$item.sourceSha256};artifacts=$artifacts}
 [IO.File]::WriteAllText((Join-Path $item.cacheDirectory 'asset.json'),($record|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
 $second=Resolve-JournalFormulaCache -InputDirectory (Split-Path $source) -CacheRoot $cache -Numbers 1 -Rule $rule
 if($second.items[0].status -ne 'hit' -or -not $second.items[0].aiSha256){throw 'Valid cache was not a hit with audit hashes'}
 $duplicates=Resolve-JournalFormulaCache -InputDirectory (Split-Path $source) -CacheRoot $cache -Numbers @(1,2) -Rule $rule
 if($duplicates.items[0].cacheKey -cne $duplicates.items[1].cacheKey){throw 'Identical source content did not share one cache key'}
 $manifestPath=Join-Path $root 'formula-cache-manifest.json'
 $prepared=(& (Join-Path $ProjectRoot '2-导入_InDesign\Prepare-JournalFormulaCache.ps1') -InputDirectory (Split-Path $source) -CacheRoot $cache -ManifestPath $manifestPath -Numbers 1 -Mode Plan|Out-String)|ConvertFrom-Json
 if($prepared.items[0].status -ne 'hit' -or -not(Test-Path -LiteralPath $prepared.logPath)){throw 'Plan manifest or event log missing'}
 $pastePlan=(& (Join-Path $ProjectRoot '2-导入_InDesign\Use-JournalFormulaNativeCache.ps1') -ManifestPath $manifestPath -Number 1 -DocumentName 'fixture_QA.indd' -MarkerText '⟦EQ-001⟧' -PlanOnly|Out-String)|ConvertFrom-Json
 if($pastePlan.action -ne 'paste-and-cache'){throw 'First native use did not plan paste-and-cache'}
 [IO.File]::WriteAllText($second.items[0].idmsPath,'idms')
 $record.artifacts.idms=[ordered]@{path=$second.items[0].idmsPath;sha256=(Get-FileHash -LiteralPath $second.items[0].idmsPath -Algorithm SHA256).Hash.ToLowerInvariant()}
 [IO.File]::WriteAllText((Join-Path $item.cacheDirectory 'asset.json'),($record|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
 $reusePlan=(& (Join-Path $ProjectRoot '2-导入_InDesign\Use-JournalFormulaNativeCache.ps1') -ManifestPath $manifestPath -Number 1 -DocumentName 'fixture_QA.indd' -MarkerText '⟦EQ-001⟧' -PlanOnly|Out-String)|ConvertFrom-Json
 if($reusePlan.action -ne 'reuse-idms'){throw 'Registered native snippet did not plan reuse'}
 # Optional diagnostics never gate cache validity: a changed PNG must not disturb
 # a verified native snippet.
 [IO.File]::AppendAllText($second.items[0].pngPath,'corrupt')
 $afterPng=Resolve-JournalFormulaCache -InputDirectory (Split-Path $source) -CacheRoot $cache -Numbers 1 -Rule $rule
 if($afterPng.items[0].status -ne 'hit' -or $afterPng.items[0].idmsStatus -ne 'ok'){throw 'Optional preview change invalidated a verified native snippet'}
 $pngPlan=(& (Join-Path $ProjectRoot '2-导入_InDesign\Use-JournalFormulaNativeCache.ps1') -ManifestPath $manifestPath -Number 1 -DocumentName 'fixture_QA.indd' -MarkerText '⟦EQ-001⟧' -PlanOnly|Out-String)|ConvertFrom-Json
 if($pngPlan.action -ne 'reuse-idms'){throw 'Optional preview change forced native regeneration'}
 # A damaged native snippet must never be placed: quarantine it and rebuild from
 # the verified AI bridge instead of trusting the AI file alone.
 [IO.File]::AppendAllText($second.items[0].idmsPath,'tampered')
 $afterIdms=Resolve-JournalFormulaCache -InputDirectory (Split-Path $source) -CacheRoot $cache -Numbers 1 -Rule $rule
 if($afterIdms.items[0].status -ne 'hit' -or $afterIdms.items[0].idmsStatus -ne 'corrupt' -or $afterIdms.items[0].nextAction -ne 'derive-idms'){throw 'Corrupt native snippet was not rejected for rebuild'}
 $rebuildPlan=(& (Join-Path $ProjectRoot '2-导入_InDesign\Use-JournalFormulaNativeCache.ps1') -ManifestPath $manifestPath -Number 1 -DocumentName 'fixture_QA.indd' -MarkerText '⟦EQ-001⟧' -PlanOnly|Out-String)|ConvertFrom-Json
 if($rebuildPlan.action -ne 'paste-and-cache'){throw 'Corrupt native snippet was reused instead of rebuilt from the AI bridge'}
 # Bridge-only records work without any optional preview, and a damaged bridge with
 # no native snippet leaves nothing usable.
 $bridge=Get-Content -LiteralPath $item.recordPath -Raw -Encoding UTF8|ConvertFrom-Json
 foreach($dropped in @('idms','pdf','png')){$bridge.artifacts.PSObject.Properties.Remove($dropped)}
 [IO.File]::WriteAllText((Join-Path $item.cacheDirectory 'asset.json'),($bridge|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
 $bridgeOnly=Resolve-JournalFormulaCache -InputDirectory (Split-Path $source) -CacheRoot $cache -Numbers 1 -Rule $rule
 if($bridgeOnly.items[0].status -ne 'hit' -or $bridgeOnly.items[0].aiStatus -ne 'ok'){throw 'AI-only bridge without optional previews was not usable'}
 [IO.File]::AppendAllText($bridgeOnly.items[0].aiPath,'tampered')
 $bridgeBroken=Resolve-JournalFormulaCache -InputDirectory (Split-Path $source) -CacheRoot $cache -Numbers 1 -Rule $rule
 if($bridgeBroken.items[0].status -ne 'invalidated'){throw 'Damaged bridge-only record was not invalidated'}
 $nextRule=Get-JournalFormulaRule -Version 'formula-outline-v2'
 $fourth=Resolve-JournalFormulaCache -InputDirectory (Split-Path $source) -CacheRoot $cache -Numbers 1 -Rule $nextRule
 if($fourth.items[0].status -ne 'miss' -or $fourth.items[0].cacheKey -eq $item.cacheKey){throw 'Rule change did not change cache identity'}
 $native=[IO.File]::ReadAllText($nativePath)
 foreach($required in @('FORMULA_DOCUMENT_NOT_OPEN','FORMULA_NOT_NATIVE_GROUP','formula-native-paste','INDESIGN_SNIPPET','formula-cache-key','journal-component-key','journal-component-hash','journal-component-kind','allGraphics.length')){if($native.IndexOf($required,[StringComparison]::Ordinal) -lt 0){throw "Native cache contract missing $required"}}
 # Illustrator has no InDesign-style document validity contract, so ownership of the
 # cleanup is proven by running the repair entry against a mocked app rather than by
 # grepping for a property test.
 $cleanupTest=Join-Path $PSScriptRoot 'run_formula_illustrator_cleanup_test.cjs'
 $node=Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue|Select-Object -First 1
 if(-not $node){throw 'Node.js is required to verify formula document cleanup'}
 $cleanupOutput=[string](& $node.Source $cleanupTest 2>&1)
 if($LASTEXITCODE -ne 0 -or $cleanupOutput -notmatch 'PASS'){throw "Formula document cleanup failed: $cleanupOutput"}
 $prepare=[IO.File]::ReadAllText((Join-Path $ProjectRoot '2-导入_InDesign\Prepare-JournalFormulaCache.ps1'))
 if($prepare.IndexOf('Group-Object cacheKey',[StringComparison]::Ordinal) -lt 0){throw 'Cache build does not deduplicate identical formulas'}
 'PASS source+rule cache identity, artifact invalidation and native IDMS contract'
}finally{Remove-Module JournalFormulaCache -ErrorAction SilentlyContinue;Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
