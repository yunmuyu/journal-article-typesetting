param(
    [Parameter(Mandatory=$true)][string]$InputDirectory,
    [Parameter(Mandatory=$true)][string]$CacheRoot,
    [Parameter(Mandatory=$true)][string]$ManifestPath,
    [int[]]$Numbers=(1..10),
    [ValidateSet('Plan','Build')][string]$Mode='Plan',
    [string]$RuleVersion='formula-outline-v4-fullwidth-source-comparisons',
    [string]$LogPath='',
    [switch]$ExportPreview=$false
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'JournalFormulaCache.psm1') -Force
if(-not $LogPath){$LogPath=Join-Path $CacheRoot 'cache-events.jsonl'}
$rule=Get-JournalFormulaRule -Version $RuleVersion
$plan=Resolve-JournalFormulaCache -InputDirectory $InputDirectory -CacheRoot $CacheRoot -Numbers $Numbers -Rule $rule
function Write-CacheEvent([object]$Item,[string]$Event){
    $parent=Split-Path -Parent $LogPath;if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    $row=[ordered]@{timestamp=[DateTime]::UtcNow.ToString('o');event=$Event;number=$Item.number;cacheKey=$Item.cacheKey;sourceSha256=$Item.sourceSha256;ruleVersion=$rule.version}
    [IO.File]::AppendAllText($LogPath,($row|ConvertTo-Json -Compress)+"`n",[Text.UTF8Encoding]::new($false))
}
foreach($item in $plan.items){Write-CacheEvent $item $item.status}
if($Mode -eq 'Build'){
    $pending=@($plan.items|Where-Object{$_.status -ne 'hit'}|Group-Object cacheKey|ForEach-Object{$_.Group[0]})
    foreach($item in $pending){
        if(Test-Path -LiteralPath $item.cacheDirectory){
            $invalidRoot=Join-Path $CacheRoot '.invalidated';New-Item -ItemType Directory -Path $invalidRoot -Force|Out-Null
            Move-Item -LiteralPath $item.cacheDirectory -Destination (Join-Path $invalidRoot ($item.cacheKey+'-'+[guid]::NewGuid().ToString('N')))
            Write-CacheEvent $item 'cache-directory-archived'
        }
        $stage=Join-Path (Join-Path $CacheRoot '.staging') ($item.cacheKey+'-'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stage -Force|Out-Null
        try{
            & (Join-Path $PSScriptRoot 'Repair-JournalFormulaAssets.ps1') -InputDirectory $InputDirectory -OutputDirectory $stage -Numbers $item.number -ExportPdf:$ExportPreview -ExportPng:$ExportPreview|Out-Null
            $sourcePrefix=Join-Path $stage ("formula-$($item.number)-10p5-simsun")
            $artifacts=[ordered]@{}
            New-Item -ItemType Directory -Path $item.cacheDirectory -Force|Out-Null
            $aiPath=$sourcePrefix+'.ai'
            if(-not(Test-Path -LiteralPath $aiPath)){throw "Formula cache build AI missing: $aiPath"}
            Move-Item -LiteralPath $aiPath -Destination (Join-Path $item.cacheDirectory 'formula.ai')
            $artifacts['ai']=[ordered]@{path='formula.ai';sha256=(Get-FileHash -LiteralPath (Join-Path $item.cacheDirectory 'formula.ai') -Algorithm SHA256).Hash.ToLowerInvariant()}
            foreach($extension in @('pdf','png')){
                $from=$sourcePrefix+'.'+$extension
                if(Test-Path -LiteralPath $from){
                    $to=Join-Path $item.cacheDirectory ('formula.'+$extension)
                    Move-Item -LiteralPath $from -Destination $to
                    $artifacts[$extension]=[ordered]@{path=('formula.'+$extension);sha256=(Get-FileHash -LiteralPath $to -Algorithm SHA256).Hash.ToLowerInvariant()}
                }
            }
            if(Test-Path -LiteralPath (Join-Path $stage 'formula-font-audit.tsv')){Move-Item -LiteralPath (Join-Path $stage 'formula-font-audit.tsv') -Destination (Join-Path $item.cacheDirectory 'font-audit.tsv')}
            if(Test-Path -LiteralPath (Join-Path $stage 'comparison-font-audit.tsv')){Move-Item -LiteralPath (Join-Path $stage 'comparison-font-audit.tsv') -Destination (Join-Path $item.cacheDirectory 'comparison-font-audit.tsv')}
            $record=[ordered]@{schemaVersion=1;cacheKey=$item.cacheKey;rule=$rule;source=[ordered]@{path=$item.sourcePath;sha256=$item.sourceSha256};artifacts=$artifacts}
            # asset.json is the commit point: a cache directory without it is never a hit,
            # so an interrupted build cannot masquerade as a finished asset. Files are
            # moved individually because Illustrator may still hold the staging DIRECTORY
            # handle after saving, which makes a directory rename fail while its files
            # are already movable.
            [IO.File]::WriteAllText((Join-Path $item.cacheDirectory 'asset.json'),($record|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
            Write-CacheEvent $item 'built'
        }catch{
            # Keep the real build error; a locked staging directory must never mask it.
            $buildError=$_
            if($item.status -eq 'hit'){
                # Never leave a half-written directory where a verified asset lived.
                $invalidRoot=Join-Path $CacheRoot '.invalidated';New-Item -ItemType Directory -Path $invalidRoot -Force|Out-Null
                try{Move-Item -LiteralPath $item.cacheDirectory -Destination (Join-Path $invalidRoot ($item.cacheKey+'-'+[guid]::NewGuid().ToString('N')))}catch{}
            }
            if(Test-Path -LiteralPath $stage){
                $resolvedStage=[IO.Path]::GetFullPath($stage)
                $stagingBoundary=[IO.Path]::GetFullPath((Join-Path $CacheRoot '.staging'))+[IO.Path]::DirectorySeparatorChar
                if(-not $resolvedStage.StartsWith($stagingBoundary,[StringComparison]::OrdinalIgnoreCase)){throw 'FORMULA_STAGE_OUTSIDE_CACHE'}
                try{Remove-Item -LiteralPath $resolvedStage -Recurse -Force -ErrorAction Stop}
                catch{Write-Warning "Formula staging directory held open, left for later cleanup: $resolvedStage"}
            }
            Write-CacheEvent $item 'build-failed'
            throw $buildError
        }
    }
    $plan=Resolve-JournalFormulaCache -InputDirectory $InputDirectory -CacheRoot $CacheRoot -Numbers $Numbers -Rule $rule
    foreach($item in $plan.items){if($item.status -ne 'hit'){throw "Formula cache build incomplete: $($item.number) $($item.status)"}}
}
$output=[ordered]@{schemaVersion=1;createdAt=[DateTime]::UtcNow.ToString('o');mode=$Mode;logPath=[IO.Path]::GetFullPath($LogPath);rule=$plan.rule;items=$plan.items}
$manifestParent=Split-Path -Parent $ManifestPath;if($manifestParent){New-Item -ItemType Directory -Path $manifestParent -Force|Out-Null}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($ManifestPath),($output|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
$output|ConvertTo-Json -Depth 12
