param(
    [Parameter(Mandatory=$true)][string]$ManifestPath,
    [Parameter(Mandatory=$true)][int]$Number,
    [Parameter(Mandatory=$true)][string]$DocumentName,
    [string]$MarkerText='',
    [string]$PlaceholderLabel='',
    [switch]$PlanOnly
)
Import-Module (Join-Path $PSScriptRoot 'JournalInDesignScript.psm1') -Force
$ErrorActionPreference='Stop'
if(($MarkerText -eq '') -eq ($PlaceholderLabel -eq '')){throw 'Specify exactly one of MarkerText or PlaceholderLabel'}
Import-Module (Join-Path $PSScriptRoot 'JournalFormulaCache.psm1') -Force
$manifestFile=(Get-Item -LiteralPath $ManifestPath).FullName
$manifest=Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8|ConvertFrom-Json
$matches=@($manifest.items|Where-Object{[int]$_.number -eq $Number})
if($matches.Count -ne 1){throw "Formula manifest number count: $Number $($matches.Count)"}
$item=$matches[0];if($item.status -ne 'hit'){throw "Formula cache is not ready: $Number $($item.status)"}
if(-not(Test-JournalFormulaArtifactRecord -RecordPath $item.recordPath -CacheKey $item.cacheKey -SourceSha256 $item.sourceSha256 -Rule $manifest.rule)){throw "Formula cache entry changed after planning: $Number"}
$record=Get-Content -LiteralPath $item.recordPath -Raw -Encoding UTF8|ConvertFrom-Json
$idmsArtifact=$record.artifacts.PSObject.Properties['idms']
$action='paste-and-cache'
if(Test-Path -LiteralPath $item.idmsPath){
    $usable=$false
    if($null -ne $idmsArtifact){
        $idmsHash=(Get-FileHash -LiteralPath $item.idmsPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $usable=($idmsHash -ceq [string]$idmsArtifact.Value.sha256)
    }
    if($usable){
        $action='reuse-idms'
    }else{
        # A damaged or unregistered native snippet must never be placed. Quarantine
        # it and rebuild from the verified AI bridge instead of failing the run.
        Move-Item -LiteralPath $item.idmsPath -Destination ($item.idmsPath+'.stale-'+[guid]::NewGuid().ToString('N'))
        if($null -ne $idmsArtifact){
            $record.artifacts.PSObject.Properties.Remove('idms')
            [IO.File]::WriteAllText($item.recordPath,($record|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
        }
    }
}
if($action -eq 'paste-and-cache' -and -not(Test-Path -LiteralPath $item.aiPath)){throw "Formula AI bridge missing for rebuild: $($item.aiPath)"}
$plan=[ordered]@{action=$action;number=$Number;documentName=$DocumentName;cacheKey=$item.cacheKey;sourceSha256=$item.sourceSha256;aiPath=$item.aiPath;idmsPath=$item.idmsPath;ruleVersion=$manifest.rule.version;markerText=$MarkerText;placeholderLabel=$PlaceholderLabel}
if($PlanOnly){$plan|ConvertTo-Json -Depth 5;return}
$jobJson=$plan|ConvertTo-Json -Compress
$entry=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_formula_native_cache.jsx'),[Text.Encoding]::UTF8)
$illustrator=$null;$aiJob=$null
if($action -eq 'paste-and-cache'){
    $aiJob=ConvertTo-Json -Compress -InputObject @{path=$item.aiPath}
    $illustrator=New-Object -ComObject Illustrator.Application.CC.2019
    try{
        $copyResult=[string]$illustrator.DoJavaScript("var JournalFormulaAiJob=$aiJob;(function(job){var f=File(job.path);for(var i=0;i<app.documents.length;i++)if(app.documents[i].fullName.fsName===f.fsName)throw Error('FORMULA_AI_ALREADY_OPEN');var d=app.open(f);if(d.textFrames.length)throw Error('FORMULA_AI_NOT_OUTLINED');d.selectObjectsOnActiveArtboard();app.copy();return 'COPIED';})(JournalFormulaAiJob);")
        if($copyResult -ne 'COPIED'){throw "Formula Illustrator copy failed: $copyResult"}
    }catch{
        # Never leave the bridge document open when the copy path fails.
        try{[void]$illustrator.DoJavaScript("(function(job){var f=File(job.path);for(var i=0;i<app.documents.length;i++)if(app.documents[i].fullName.fsName===f.fsName){app.documents[i].close(SaveOptions.DONOTSAVECHANGES);return 'CLOSED';}return 'ALREADY_CLOSED';})($aiJob);")}catch{}
        throw
    }
}
$indesign=New-Object -ComObject InDesign.Application.2020
try{
    $result=[string](Invoke-JournalInDesignScript -Application $indesign -Code ("var JournalFormulaNativeCacheJob=$jobJson;var __formulaCacheResult;try{__formulaCacheResult="+$entry+"}catch(e){__formulaCacheResult='ERROR '+e+' LINE '+e.line;}__formulaCacheResult;"))
}finally{
    if($action -eq 'paste-and-cache'){
        $closed=[string]$illustrator.DoJavaScript("(function(job){var f=File(job.path);for(var i=0;i<app.documents.length;i++)if(app.documents[i].fullName.fsName===f.fsName){app.documents[i].close(SaveOptions.DONOTSAVECHANGES);return 'CLOSED';}return 'ALREADY_CLOSED';})($aiJob);")
        if($closed -notin @('CLOSED','ALREADY_CLOSED')){throw 'FORMULA_AI_CLOSE_IDENTITY'}
    }
}
if($result.StartsWith('Error') -or $result.StartsWith('ERROR')){throw $result}
if($action -eq 'paste-and-cache'){
    if(-not(Test-Path -LiteralPath $item.idmsPath)){throw 'Formula IDMS export missing'}
    $idms=[pscustomobject][ordered]@{path='formula.idms';sha256=(Get-FileHash -LiteralPath $item.idmsPath -Algorithm SHA256).Hash.ToLowerInvariant()}
    if($null -eq $record.artifacts.PSObject.Properties['idms']){$record.artifacts|Add-Member -NotePropertyName idms -NotePropertyValue $idms}else{$record.artifacts.idms=$idms}
    [IO.File]::WriteAllText($item.recordPath,($record|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
}
if($null -eq $item.PSObject.Properties['nativeAction']){$item|Add-Member -NotePropertyName nativeAction -NotePropertyValue $action}else{$item.nativeAction=$action}
if($null -eq $item.PSObject.Properties['idmsSha256']){$item|Add-Member -NotePropertyName idmsSha256 -NotePropertyValue ((Get-FileHash -LiteralPath $item.idmsPath -Algorithm SHA256).Hash.ToLowerInvariant())}else{$item.idmsSha256=(Get-FileHash -LiteralPath $item.idmsPath -Algorithm SHA256).Hash.ToLowerInvariant()}
[IO.File]::WriteAllText($manifestFile,($manifest|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
$event=[ordered]@{timestamp=[DateTime]::UtcNow.ToString('o');event=$action;number=$Number;cacheKey=$item.cacheKey;documentName=$DocumentName;result=$result}
[IO.File]::AppendAllText([string]$manifest.logPath,($event|ConvertTo-Json -Compress)+"`n",[Text.UTF8Encoding]::new($false))
$event|ConvertTo-Json -Depth 5
