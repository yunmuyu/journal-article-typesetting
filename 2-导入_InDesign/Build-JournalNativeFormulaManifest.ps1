param(
    [Parameter(Mandatory=$true)][string]$FormulaSourceMap,
    [Parameter(Mandatory=$true)][string]$InputDirectory,
    [Parameter(Mandatory=$true)][string]$CacheRoot,
    [Parameter(Mandatory=$true)][string]$ManifestPath,
    [Parameter(Mandatory=$true)][string]$WorkingDirectory,
    [switch]$PlanOnly
)
Import-Module (Join-Path $PSScriptRoot 'JournalInDesignScript.psm1') -Force
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'JournalFormulaCache.psm1') -Force
$mapPath=(Get-Item -LiteralPath $FormulaSourceMap).FullName
$inputRoot=(Get-Item -LiteralPath $InputDirectory).FullName
$cachePath=[IO.Path]::GetFullPath($CacheRoot)
$workingPath=[IO.Path]::GetFullPath($WorkingDirectory)
$outputPath=[IO.Path]::GetFullPath($ManifestPath)
$map=Get-Content -LiteralPath $mapPath -Raw -Encoding UTF8|ConvertFrom-Json
$mapHash=(Get-FileHash -LiteralPath $mapPath -Algorithm SHA256).Hash
if($map.schemaVersion -ne 1){throw 'FORMULA_SOURCE_MAP_VERSION'}
if($map.PSObject.Properties['omml'] -and @($map.omml).Count){throw 'FORMULA_OMML_UNSUPPORTED'}
if(-not(Test-Path -LiteralPath $map.source -PathType Leaf)){throw 'FORMULA_SOURCE_WORD_MISSING'}
if((Get-FileHash -LiteralPath $map.source -Algorithm SHA256).Hash -ine $map.sourceSha256){throw 'FORMULA_SOURCE_WORD_CHANGED'}
$formulas=@($map.formulas|Sort-Object number)
if(-not $formulas.Count){throw 'FORMULA_SOURCE_MAP_EMPTY'}
$seen=@{};$displayNumbers=[ordered]@{}
foreach($formula in $formulas){
    $number=[int]$formula.number
    if($number -lt 1 -or $number -ne [double]$formula.number -or $seen.ContainsKey($number)){throw 'FORMULA_SOURCE_NUMBER'}
    $seen[$number]=$true
    if([string]$formula.marker -cne ('⟦EQ-'+$number.ToString('000')+'⟧')){throw "FORMULA_SOURCE_MARKER $number"}
    $sourcePath=Join-Path $inputRoot "formula-$number.wmf"
    if(-not(Test-Path -LiteralPath $sourcePath -PathType Leaf)){throw "FORMULA_WMF_MISSING $number"}
    if([IO.Path]::GetFullPath([string]$formula.path) -ine [IO.Path]::GetFullPath($sourcePath)){throw "FORMULA_SOURCE_PATH $number"}
    if((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ine [string]$formula.preview.sha256){throw "FORMULA_WMF_CHANGED $number"}
    if(-not $formula.PSObject.Properties['displayNumber']){throw "FORMULA_DISPLAY_NUMBER_REQUIRED $number"}
    if($null -ne $formula.displayNumber -and [string]$formula.displayNumber -notmatch '^\d+$'){throw "FORMULA_DISPLAY_NUMBER_INVALID $number"}
    $displayNumbers[[string]$number]=$formula.displayNumber
}
$rule=Get-JournalFormulaRule
$cachePlan=Resolve-JournalFormulaCache -InputDirectory $inputRoot -CacheRoot $cachePath -Numbers @($formulas.number) -Rule $rule
$plan=[ordered]@{mode='native-idms';status='planned';sourceMap=$mapPath;sourceMapSHA256=$mapHash;formula_count=$formulas.Count;uniqueMaterials=@($cachePlan.items.cacheKey|Sort-Object -Unique).Count;displayNumbers=$displayNumbers;items=$cachePlan.items;manifestPath=$outputPath;workingDirectory=$workingPath}
if($PlanOnly){$plan|ConvertTo-Json -Depth 14;return}
if(Test-Path -LiteralPath $outputPath){throw 'FORMULA_NATIVE_MANIFEST_EXISTS'}
$runDirectory=Join-Path $workingPath ('native-formula-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runDirectory -Force|Out-Null
$assetManifest=Join-Path $runDirectory 'asset-cache-manifest.json'
& (Join-Path $PSScriptRoot 'Prepare-JournalFormulaCache.ps1') -InputDirectory $inputRoot -CacheRoot $cachePath -ManifestPath $assetManifest -Numbers @($formulas.number) -Mode Build|Out-Null
$cacheDocument=Join-Path $runDirectory ('native_formula_cache_'+[guid]::NewGuid().ToString('N')+'_QA.indd')
$documentJob=@{path=$cacheDocument;markers=@($formulas.marker)}|ConvertTo-Json -Compress
$app=New-Object -ComObject InDesign.Application.2020
$created=(Invoke-JournalInDesignScript -Application $app -Code (@"
(function(job){try{
 var target=File(job.path);if(target.exists)throw Error('CACHE_DOCUMENT_EXISTS');
 var d=app.documents.add().getElements()[0];d.documentPreferences.facingPages=false;d.documentPreferences.pagesPerDocument=1;
 d.documentPreferences.pageWidth='210mm';d.documentPreferences.pageHeight='297mm';
 d.viewPreferences.horizontalMeasurementUnits=MeasurementUnits.MILLIMETERS;d.viewPreferences.verticalMeasurementUnits=MeasurementUnits.MILLIMETERS;
 d.viewPreferences.rulerOrigin=RulerOrigin.PAGE_ORIGIN;d.zeroPoint=[0,0];
 for(var i=0;i<job.markers.length;i++){var p=i?d.pages.add():d.pages[0];var f=p.textFrames.add({geometricBounds:[20,20,277,190]});f.contents=job.markers[i];}
 d.insertLabel('journal-native-cache-build','true');d.save(target);return 'OK\t'+d.id+'\t'+d.name;
}catch(e){return 'ERROR '+e+' LINE '+e.line;}})($documentJob);
"@))
$createdParts=([string]$created).Split("`t")
if($createdParts.Count -ne 3 -or $createdParts[0] -ne 'OK'){throw "FORMULA_CACHE_DOCUMENT_CREATE $created"}
$documentId=[int]$createdParts[1];$documentName=$createdParts[2]
$identity=@{id=$documentId;path=$cacheDocument}|ConvertTo-Json -Compress
$entries=[Collections.Generic.List[object]]::new()
try{
    foreach($formula in $formulas){
        $number=[int]$formula.number
        & (Join-Path $PSScriptRoot 'Use-JournalFormulaNativeCache.ps1') -ManifestPath $assetManifest -Number $number -DocumentName $documentName -MarkerText $formula.marker|Out-Null
        $measurementJob=@{id=$documentId;path=$cacheDocument;number=$number}|ConvertTo-Json -Compress
        $measurement=[string](Invoke-JournalInDesignScript -Application $app -Code (@"
(function(job){try{
 var d=app.documents.itemByID(job.id).getElements()[0];if(!d.isValid||String(d.fullName.fsName).toLowerCase()!==String(File(job.path).fsName).toLowerCase()||d.extractLabel('journal-native-cache-build')!=='true')throw Error('CACHE_DOCUMENT_IDENTITY');
 var found=[],items=d.allPageItems;for(var i=0;i<items.length;i++)if(items[i].label==='source-formula-'+job.number)found.push(items[i]);
 if(found.length!==1)throw Error('CACHE_FORMULA_COUNT');var g=found[0];
 if(g.constructor.name!=='Group'||g.allGraphics.length||g.extractLabel('formula-native-paste')!=='true'||Number(g.extractLabel('formula-base-point-size'))!==10.5)throw Error('CACHE_FORMULA_PROVENANCE');
 if(Math.abs(g.absoluteHorizontalScale-100)>.001||Math.abs(g.absoluteVerticalScale-100)>.001)throw Error('CACHE_FORMULA_SCALE');
 d.recompose();var b=g.geometricBounds,w=b[3]-b[1],h=b[2]-b[0];if(!(w>0&&h>0))throw Error('CACHE_FORMULA_GEOMETRY');
 return ['OK',w,h].join('\t');
}catch(e){return 'ERROR '+e+' LINE '+e.line;}})($measurementJob);
"@))
        $parts=$measurement.Split("`t")
        if($parts.Count -ne 3 -or $parts[0] -ne 'OK'){throw "FORMULA_CACHE_MEASUREMENT $number $measurement"}
        $cache=Get-Content -LiteralPath $assetManifest -Raw -Encoding UTF8|ConvertFrom-Json
        $item=@($cache.items|Where-Object{[int]$_.number -eq $number})[0]
        $idmsHash=(Get-FileHash -LiteralPath $item.idmsPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if($idmsHash -cne $item.idmsSha256){throw "FORMULA_CACHE_IDMS_HASH $number"}
        $entries.Add([ordered]@{number=$number;marker=$formula.marker;path=$item.idmsPath;sha256=$idmsHash;widthMm=[double]::Parse($parts[1],[Globalization.CultureInfo]::InvariantCulture);heightMm=[double]::Parse($parts[2],[Globalization.CultureInfo]::InvariantCulture);basePointSize=10.5;cacheKey=$item.cacheKey;sourceSha256=$item.sourceSha256;ruleVersion=$cache.rule.version;inline=[bool]$formula.inline;displayNumber=$formula.displayNumber})
    }
    if((Get-FileHash -LiteralPath $mapPath -Algorithm SHA256).Hash -cne $mapHash){throw 'FORMULA_SOURCE_MAP_CHANGED'}
    $result=[ordered]@{schemaVersion=1;mode='native-idms';formula_count=$formulas.Count;entries=@($entries);displayNumbers=$displayNumbers;sourceMap=$mapPath;sourceMapSHA256=$mapHash;sourceWord=$map.source;sourceWordSHA256=$map.sourceSha256;cacheManifest=$assetManifest;cacheDocument=$cacheDocument;createdAt=[DateTime]::UtcNow.ToString('o')}
    $parent=Split-Path -Parent $outputPath;if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    $temporary=$outputPath+'.tmp-'+[guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($temporary,($result|ConvertTo-Json -Depth 14),[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $outputPath
    $result|ConvertTo-Json -Depth 14
}finally{
    $closed=[string](Invoke-JournalInDesignScript -Application $app -Code (@"
(function(job){try{var d=app.documents.itemByID(job.id).getElements()[0];if(!d.isValid||String(d.fullName.fsName).toLowerCase()!==String(File(job.path).fsName).toLowerCase()||d.extractLabel('journal-native-cache-build')!=='true')throw Error('CACHE_DOCUMENT_IDENTITY');d.save();d.close(SaveOptions.YES);return 'CLOSED';}catch(e){return 'ERROR '+e+' LINE '+e.line;}})($identity);
"@))
    if($closed -ne 'CLOSED'){Write-Warning "Formula cache QA document retained: $closed"}
}
