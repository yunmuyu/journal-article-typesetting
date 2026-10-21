Set-StrictMode -Version Latest

# The rule below is hashed verbatim into every cache key. Its shape, key order and
# values are frozen: changing any of them orphans all previously built assets.
# Format expectations deliberately stay OUT of this object -- they are policy, not
# identity -- and live in Get-JournalFormulaFormatPolicy instead.
function Get-JournalFormulaRule {
    param([string]$Version='formula-outline-v4-fullwidth-source-comparisons')
    [ordered]@{
        version=$Version
        basePointSize=10.5
        comparisonFont='SimSun'
        comparisonCharacters=@('≤','≥')
        outlined=$true
        auditFormats=@('ai','pdf','png')
    }
}

# Not part of any cache key. The native product is the IDMS outline group; the AI
# file is only the bridge used when IDMS has not been derived yet. Per-formula
# PDF/PNG are optional diagnostics and must never gate cache validity.
function Get-JournalFormulaFormatPolicy {
    [ordered]@{bridge='ai';native='idms';diagnostic=@('pdf','png')}
}

function Get-JournalFormulaCacheKey {
    param(
        [Parameter(Mandatory=$true)][string]$SourcePath,
        [Parameter(Mandatory=$true)]$Rule
    )
    $source=(Get-Item -LiteralPath $SourcePath).FullName
    $ruleJson=$Rule|ConvertTo-Json -Depth 10 -Compress
    $hash=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
    try{
        $hash.AppendData([IO.File]::ReadAllBytes($source))
        $hash.AppendData([Text.Encoding]::UTF8.GetBytes("`nJOURNAL_FORMULA_RULE`n"+$ruleJson))
        ([Convert]::ToHexString($hash.GetHashAndReset())).ToLowerInvariant()
    }finally{$hash.Dispose()}
}

function Get-JournalFormulaArtifactState {
    param(
        [Parameter(Mandatory=$true)]$Record,
        [Parameter(Mandatory=$true)][string]$RecordPath,
        [Parameter(Mandatory=$true)][string]$Name
    )
    $recordDirectory=Split-Path -Parent $RecordPath
    $property=$Record.artifacts.PSObject.Properties[$Name]
    if($null -eq $property -or $null -eq $property.Value){return [pscustomobject]@{status='absent';path='';sha256=''}}
    $declared=[string]$property.Value.path
    $declaredSha=[string]$property.Value.sha256
    if(-not $declared){return [pscustomobject]@{status='corrupt';path='';sha256=''}}
    $path=if([IO.Path]::IsPathRooted($declared)){$declared}else{Join-Path $recordDirectory $declared}
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return [pscustomobject]@{status='corrupt';path=$path;sha256=''}}
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actual -cne $declaredSha){return [pscustomobject]@{status='corrupt';path=$path;sha256=''}}
    [pscustomobject]@{status='ok';path=$path;sha256=$actual}
}

function Test-JournalFormulaArtifactRecord {
    param(
        [Parameter(Mandatory=$true)][string]$RecordPath,
        [Parameter(Mandatory=$true)][string]$CacheKey,
        [Parameter(Mandatory=$true)][string]$SourceSha256,
        [Parameter(Mandatory=$true)]$Rule
    )
    try{$record=Get-Content -LiteralPath $RecordPath -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $false}
    if([string]$record.cacheKey -cne $CacheKey -or [string]$record.source.sha256 -cne $SourceSha256){return $false}
    if(($record.rule|ConvertTo-Json -Depth 10 -Compress) -cne ($Rule|ConvertTo-Json -Depth 10 -Compress)){return $false}
    # Native product wins; the AI bridge only stands in until IDMS exists.
    # Diagnostic exports (pdf/png) are recorded but never required. A corrupt
    # artifact disqualifies its own layer only: a damaged IDMS is rebuilt from a
    # verified AI bridge, and a damaged AI file is irrelevant once verified IDMS
    # exists. Only a record with no usable layer at all is rejected.
    foreach($name in @('idms','ai')){
        $state=Get-JournalFormulaArtifactState -Record $record -RecordPath $RecordPath -Name $name
        if($state.status -eq 'ok'){return $true}
    }
    $false
}

function Resolve-JournalFormulaCache {
    param(
        [Parameter(Mandatory=$true)][string]$InputDirectory,
        [Parameter(Mandatory=$true)][string]$CacheRoot,
        [Parameter(Mandatory=$true)][int[]]$Numbers,
        [Parameter(Mandatory=$true)]$Rule
    )
    $inputRoot=(Get-Item -LiteralPath $InputDirectory).FullName
    $items=[Collections.Generic.List[object]]::new()
    foreach($number in $Numbers){
        if($number -lt 1){throw 'Formula number must be positive'}
        $source=Join-Path $inputRoot "formula-$number.wmf"
        if(-not(Test-Path -LiteralPath $source)){throw "Formula source missing: $source"}
        $sourceSha=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
        $key=Get-JournalFormulaCacheKey -SourcePath $source -Rule $Rule
        $directory=Join-Path (Join-Path (Join-Path $CacheRoot $Rule.version) $key.Substring(0,2)) $key
        $recordPath=Join-Path $directory 'asset.json'
        $status=if(Test-Path -LiteralPath $recordPath){if(Test-JournalFormulaArtifactRecord -RecordPath $recordPath -CacheKey $key -SourceSha256 $sourceSha -Rule $Rule){'hit'}else{'invalidated'}}else{'miss'}
        $record=if(Test-Path -LiteralPath $recordPath){try{Get-Content -LiteralPath $recordPath -Raw -Encoding UTF8|ConvertFrom-Json}catch{$null}}else{$null}
        $idmsState=[pscustomobject]@{status='absent';path='';sha256=''}
        $aiState=[pscustomobject]@{status='absent';path='';sha256=''}
        if($record){
            $idmsState=Get-JournalFormulaArtifactState -Record $record -RecordPath $recordPath -Name 'idms'
            $aiState=Get-JournalFormulaArtifactState -Record $record -RecordPath $recordPath -Name 'ai'
        }
        $nativeReady=($status -eq 'hit' -and $idmsState.status -eq 'ok')
        $bridgeReady=($status -eq 'hit' -and $aiState.status -eq 'ok')
        $action=if($status -ne 'hit'){'rebuild'}elseif($nativeReady){'reuse-idms'}else{'derive-idms'}
        $items.Add([pscustomobject][ordered]@{
            number=$number;status=$status;sourcePath=$source;sourceSha256=$sourceSha;cacheKey=$key;cacheDirectory=$directory
            aiPath=(Join-Path $directory 'formula.ai');pdfPath=(Join-Path $directory 'formula.pdf');pngPath=(Join-Path $directory 'formula.png')
            idmsPath=(Join-Path $directory 'formula.idms');recordPath=$recordPath
            aiStatus=$aiState.status;idmsStatus=$idmsState.status;nativeReady=$nativeReady;bridgeReady=$bridgeReady;nextAction=$action
            aiSha256=[string]$aiState.sha256;idmsSha256=[string]$idmsState.sha256
        })
    }
    [pscustomobject][ordered]@{schemaVersion=1;rule=$Rule;items=@($items)}
}

Export-ModuleMember -Function Get-JournalFormulaRule,Get-JournalFormulaFormatPolicy,Get-JournalFormulaArtifactState,Get-JournalFormulaCacheKey,Test-JournalFormulaArtifactRecord,Resolve-JournalFormulaCache
