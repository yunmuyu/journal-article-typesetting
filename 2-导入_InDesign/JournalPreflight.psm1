Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

function Read-JournalJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing JSON: $Path" }
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-JournalJsonAtomic {
    param([object]$Value, [string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $parent = [IO.Path]::GetDirectoryName($full)
    if (-not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent) }
    $temp = "$full.$([guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $full -Force
}

function Get-JournalRasterMetrics {
    param([string]$Path)
    Add-Type -AssemblyName System.Drawing
    $bitmap = [Drawing.Bitmap]::FromFile($Path)
    try {
        $left = $bitmap.Width; $top = $bitmap.Height; $right = -1; $bottom = -1
        $step = [math]::Max(1, [math]::Floor([math]::Max($bitmap.Width, $bitmap.Height) / 900))
        for ($y = 0; $y -lt $bitmap.Height; $y += $step) {
            for ($x = 0; $x -lt $bitmap.Width; $x += $step) {
                $pixel = $bitmap.GetPixel($x, $y)
                if ($pixel.A -gt 12 -and ($pixel.R -lt 246 -or $pixel.G -lt 246 -or $pixel.B -lt 246)) {
                    if ($x -lt $left) { $left = $x }; if ($x -gt $right) { $right = $x }
                    if ($y -lt $top) { $top = $y }; if ($y -gt $bottom) { $bottom = $y }
                }
            }
        }
        if ($right -lt 0) { return [pscustomobject]@{ widthPx=$bitmap.Width; heightPx=$bitmap.Height; margins=@{left=1;right=1;top=1;bottom=1}; contentRatio=0 } }
        [pscustomobject]@{
            widthPx = $bitmap.Width; heightPx = $bitmap.Height
            margins = [ordered]@{
                left = [math]::Round($left / $bitmap.Width, 4)
                right = [math]::Round(($bitmap.Width - 1 - $right) / $bitmap.Width, 4)
                top = [math]::Round($top / $bitmap.Height, 4)
                bottom = [math]::Round(($bitmap.Height - 1 - $bottom) / $bitmap.Height, 4)
            }
            contentRatio = [math]::Round((($right-$left+1)*($bottom-$top+1))/($bitmap.Width*$bitmap.Height), 4)
        }
    } finally { $bitmap.Dispose() }
}

function Get-JournalAssetMetrics {
    param([string]$Path, [string]$CacheDirectory)
    $full = (Get-Item -LiteralPath $Path).FullName
    $sha256 = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
    $cacheRecord = $null
    if ($CacheDirectory) {
        $cacheRecord = Join-Path (Join-Path ([IO.Path]::GetFullPath($CacheDirectory)) $sha256.Substring(0, 2)) ($sha256 + '.json')
        if (Test-Path -LiteralPath $cacheRecord -PathType Leaf) {
            $cached = Read-JournalJson $cacheRecord
            if ($cached.schemaVersion -eq 1 -and $cached.sha256 -eq $sha256) {
                $cached.path=$full;$cached.name=[IO.Path]::GetFileName($full)
                $cached | Add-Member -NotePropertyName cache -NotePropertyValue ([pscustomobject]@{ status='hit'; recordPath=$cacheRecord }) -Force
                return $cached
            }
        }
    }
    $extension = [IO.Path]::GetExtension($full).ToLowerInvariant()
    $preview = $full; $widthMm = $null; $heightMm = $null; $compatible = $true; $reason = ''; $descriptorCount=0; $missingCapHeight=0
    $pageBoxes = [ordered]@{}; $fonts = @(); $contentType = 'raster'
    if ($extension -eq '.pdf') {
        $pdfinfo = Get-Command pdfinfo -ErrorAction SilentlyContinue
        $pdftoppm = Get-Command pdftoppm -ErrorAction SilentlyContinue
        if (-not $pdfinfo -or -not $pdftoppm) { throw 'pdfinfo and pdftoppm are required for PDF preflight' }
        $details = & $pdfinfo.Source '-box' $full 2>&1
        if ($LASTEXITCODE -ne 0) { $compatible = $false; $reason = ($details -join ' ') }
        foreach($boxName in @('MediaBox','CropBox','BleedBox','TrimBox','ArtBox')) {
            $boxLine = @($details | Where-Object { $_ -match "^${boxName}:\s+([-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)" } | Select-Object -First 1)
            if($boxLine.Count) { [void]($boxLine[0] -match "^${boxName}:\s+([-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)"); $pageBoxes[$boxName]=@([double]$Matches[1],[double]$Matches[2],[double]$Matches[3],[double]$Matches[4]) }
        }
        $ascii=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($full))
        $objects=[regex]::Matches($ascii,'(?ms)\d+\s+\d+\s+obj\s*(?<body>.*?)\s*endobj')
        $descriptors=@($objects|Where-Object{$_.Groups['body'].Value -match '/Type\s*/FontDescriptor'});$descriptorCount=$descriptors.Count
        $fonts=@([regex]::Matches($ascii,'/BaseFont\s*/(?<name>[^\s/<>{}\[\]()]+)')|ForEach-Object{$_.Groups['name'].Value}|Sort-Object -Unique)
        $missingCapHeight=@($descriptors|Where-Object{$_.Groups['body'].Value -notmatch '/CapHeight\b'}).Count
        $imageCount=([regex]::Matches($ascii,'/Subtype\s*/Image\b')).Count
        $contentType=if($imageCount -gt 0 -and ($descriptorCount -gt 0 -or $ascii -match '(?m)(?:^|\s)[mlc]\s')){'mixed'}elseif($imageCount -gt 0){'raster'}else{'vector'}
        if($missingCapHeight){$compatible=$false;$reason="$missingCapHeight visible font descriptors have no CapHeight"}
        $sizeLine = @($details | Where-Object { $_ -match '^Page size:\s+([0-9.]+) x ([0-9.]+) pts' })
        if ($sizeLine.Count) { [void]($sizeLine[0] -match '^Page size:\s+([0-9.]+) x ([0-9.]+) pts'); $widthMm=[math]::Round([double]$Matches[1]*25.4/72,3); $heightMm=[math]::Round([double]$Matches[2]*25.4/72,3) }
        $tempBase = Join-Path ([IO.Path]::GetTempPath()) ('journal-preflight-'+[guid]::NewGuid().ToString('N'))
        if ($compatible) {
            $render = & $pdftoppm.Source '-f' '1' '-singlefile' '-r' '36' '-png' $full $tempBase 2>&1
            if ($LASTEXITCODE -ne 0) { $compatible=$false; $reason=($render -join ' ') } else { $preview="$tempBase.png" }
        }
    }
    try {
        $raster = if ($compatible) { Get-JournalRasterMetrics $preview } else { $null }
        if ($null -eq $widthMm -and $raster) { $widthMm=[math]::Round($raster.widthPx*25.4/96,3); $heightMm=[math]::Round($raster.heightPx*25.4/96,3) }
        $recommendedScale=if($widthMm -and $widthMm -gt 0){[math]::Round([math]::Min(100,82.5/$widthMm*100),2)}else{100}
        $metric=[pscustomobject]@{schemaVersion=1;path=$full;name=[IO.Path]::GetFileName($full);extension=$extension;sha256=$sha256;widthMm=$widthMm;heightMm=$heightMm;pageBoxes=[pscustomobject]$pageBoxes;fonts=@($fonts);contentType=$contentType;recommendedScalePercent=$recommendedScale;pdfCompatible=$compatible;compatibilityError=$reason;visibleFontDescriptors=$descriptorCount;missingCapHeight=$missingCapHeight;raster=$raster}
        if($cacheRecord){Write-JournalJsonAtomic $metric $cacheRecord}
        $metric|Add-Member -NotePropertyName cache -NotePropertyValue ([pscustomobject]@{status='miss';recordPath=$cacheRecord}) -Force
        $metric
    } finally { if ($preview -ne $full -and (Test-Path -LiteralPath $preview)) { Remove-Item -LiteralPath $preview -Force } }
}

function Get-JournalFigureNumber {
    param([string]$Name)
    if ($Name -match '(?:^|[-_ ])图\s*(\d+)(?:[._-](\d+))?') { return [pscustomobject]@{ number=[int]$Matches[1]; part=if($Matches[2]){[int]$Matches[2]}else{$null} } }
    $null
}

function Get-JournalFigureChoice {
    param([object]$Context)
    $number = [int]$Context.number; $author=[string]$Context.author; $files=@($Context.files)
    $tagged = @($files | ForEach-Object { $n=Get-JournalFigureNumber $_.BaseName; if($n -and $n.number -eq $number){[pscustomobject]@{file=$_;part=$n.part}} })
    $exact = @($tagged | Where-Object { $null -eq $_.part -and $_.file.BaseName -eq "$author-图$number" })
    if ($exact.Count -eq 1) { return [pscustomobject]@{ assets=@($exact[0].file); issue=$null } }
    $parts = @($tagged | Where-Object { $null -ne $_.part } | Sort-Object part)
    if ($parts.Count -gt 1 -and $parts.Count -eq $tagged.Count) { return [pscustomobject]@{ assets=@($parts.file); issue=$null } }
    if ($tagged.Count -eq 1) { return [pscustomobject]@{ assets=@($tagged[0].file); issue="Figure $number filename is not $author-图$number" } }
    if ($tagged.Count -eq 0) { return [pscustomobject]@{ assets=@(); issue="Figure $number is missing" } }
    [pscustomobject]@{ assets=@(); issue="Figure $number has ambiguous candidates: $(@($tagged.file.Name) -join ', ')" }
}

function New-JournalPreflightPlan {
    param([object]$Task)
    $issues = [Collections.Generic.List[object]]::new(); $warnings = [Collections.Generic.List[object]]::new()
    foreach($field in @('taskId','author','sourceWord','articleJson','figureDirectory','outputDirectory')) { if(-not $Task.PSObject.Properties[$field] -or -not [string]$Task.$field){$issues.Add([pscustomobject]@{code='MANIFEST_FIELD';message="Missing $field"})} }
    if($issues.Count){$items=@($issues);return [pscustomobject]@{taskId=if($Task.PSObject.Properties['taskId']){$Task.taskId}else{$null};status='needs_input';pipeline=$null;issues=$items;exceptionSummary=[ordered]@{needsInput=$true;count=$items.Count;codes=@($items|ForEach-Object{$_.code}|Sort-Object -Unique);items=$items};warnings=@();assets=@();layout=$null}}
    foreach($field in @('sourceWord','articleJson','figureDirectory')) { if(-not(Test-Path -LiteralPath $Task.$field)){$issues.Add([pscustomobject]@{code='INPUT_MISSING';message="$field does not exist: $($Task.$field)"})} }
    if($issues.Count){$items=@($issues);return [pscustomobject]@{taskId=$Task.taskId;status='needs_input';pipeline=$null;issues=$items;exceptionSummary=[ordered]@{needsInput=$true;count=$items.Count;codes=@($items|ForEach-Object{$_.code}|Sort-Object -Unique);items=$items};warnings=@();assets=@();layout=$null}}
    $article=Read-JournalJson $Task.articleJson; $blocks=@($article.blocks)
    $assetCacheDirectory=if($Task.PSObject.Properties['assetCacheDirectory'] -and [string]$Task.assetCacheDirectory){[string]$Task.assetCacheDirectory}else{Join-Path $Task.outputDirectory '.asset-metadata-cache'}
    $captions=@($blocks|Where-Object{$_.role -eq 'figure_caption' -and $_.text -match '^图\s*(\d+)\s*\S'}|ForEach-Object{[pscustomobject]@{number=[int]$Matches[1];text=$_.text;block=[array]::IndexOf($blocks,$_)} }|Sort-Object number -Unique)
    $figureFiles=@(Get-ChildItem -LiteralPath $Task.figureDirectory -File -Recurse|Where-Object{$_.Extension -match '^\.(pdf|jpe?g|png|tiff?)$'})
    $assets=[Collections.Generic.List[object]]::new()
    foreach($caption in $captions){
        $choice=Get-JournalFigureChoice ([pscustomobject]@{number=$caption.number;author=$Task.author;files=$figureFiles})
        if($choice.issue){$issues.Add([pscustomobject]@{code=if($choice.assets.Count){'FIGURE_NAME'}elseif($choice.issue -match 'missing'){'FIGURE_MISSING'}else{'FIGURE_AMBIGUOUS'};message=$choice.issue})}
        foreach($file in @($choice.assets)){
            $metric=Get-JournalAssetMetrics $file.FullName $assetCacheDirectory; $assets.Add($metric)
            if(-not $metric.pdfCompatible){$issues.Add([pscustomobject]@{code='PDF_INCOMPATIBLE';message="$($metric.name): $($metric.compatibilityError)"})}
            $marginValues=if($metric.raster -and $metric.raster.margins -is [Collections.IDictionary]){@($metric.raster.margins.Values)}elseif($metric.raster){@($metric.raster.margins.PSObject.Properties|ForEach-Object{$_.Value})}else{@()}
            if($metric.raster -and ((($marginValues|Measure-Object -Maximum).Maximum) -ge .25 -or $metric.raster.contentRatio -lt .35)){
                $reviews=@(if($Task.PSObject.Properties['figureWhitespaceReviews']){$Task.figureWhitespaceReviews})
                $approved=@($reviews|Where-Object{$_.name -ceq $metric.name -and $_.sha256 -ieq $metric.sha256 -and -not [string]::IsNullOrWhiteSpace([string]$_.reason)})
                if($approved.Count -eq 1 -and $metric.raster.contentRatio -gt 0){$warnings.Add([pscustomobject]@{code='FIGURE_WHITESPACE_REVIEWED';message="$($metric.name): $($approved[0].reason)";sha256=$metric.sha256})}
                else{$issues.Add([pscustomobject]@{code='FIGURE_WHITESPACE';message="$($metric.name) has unusually large white margins"})}
            }
        }
    }
    $captionNumbers=@($captions|ForEach-Object{$_.number})
    $uncaptioned=@($figureFiles|Where-Object{ $n=Get-JournalFigureNumber $_.BaseName; $n -and $captionNumbers -notcontains $n.number })
    if($uncaptioned.Count){$warnings.Add([pscustomobject]@{code='UNUSED_FIGURE';message="Unmatched files: $(@($uncaptioned.Name)-join ', ')"})}
    $tables=@(if($Task.PSObject.Properties['tableJson'] -and (Test-Path -LiteralPath $Task.tableJson)){ $raw=Read-JournalJson $Task.tableJson; if($raw.PSObject.Properties['tables']){@($raw.tables)}else{@($raw)} })
    $markerCount=([regex]::Matches((@($blocks.text)-join "`n"),'⟦EQ-\d+⟧')).Count
    foreach($table in $tables){
        foreach($row in @($table.rows)){
            foreach($cell in @($row)){
                $markerCount+=([regex]::Matches([string]$cell,'⟦EQ-\d+⟧')).Count
            }
        }
    }
    $formulaCount=if($markerCount){$markerCount}else{@($blocks|Where-Object{$_.role -eq 'math'}).Count}
    if($formulaCount -gt 0 -and (-not $Task.PSObject.Properties['formulaManifest'] -or -not(Test-Path -LiteralPath $Task.formulaManifest))){$issues.Add([pscustomobject]@{code='FORMULA_MANIFEST';message="$formulaCount formulas require a formula manifest"})}
    elseif($formulaCount -gt 0){$formulaManifest=Read-JournalJson $Task.formulaManifest;$manifestCount=if($formulaManifest.PSObject.Properties['formula_count']){[int]$formulaManifest.formula_count}else{@($formulaManifest.formulas).Count};if($manifestCount -ne $formulaCount){$issues.Add([pscustomobject]@{code='FORMULA_COUNT';message="Article has $formulaCount formula markers but manifest has $manifestCount"})}}
    $bodyChars=(@($blocks|Where-Object{$_.role -in @('body','heading1','heading2','reference_item','author_bio')}|ForEach-Object{[string]$_.text})-join '').Length
    $figurePlans=[Collections.Generic.List[object]]::new(); $widePoints=[Collections.Generic.List[object]]::new();$wideBoundaries=[Collections.Generic.List[object]]::new()
    foreach($caption in $captions){
        $selected=@($assets|Where-Object{(Get-JournalFigureNumber ([IO.Path]::GetFileNameWithoutExtension($_.name))).number -eq $caption.number})
        $width=if($selected.Count){($selected|Measure-Object widthMm -Maximum).Maximum}else{0}
        $mode=if($selected.Count -ge 3 -and @($selected|Where-Object{$_.extension -ne '.pdf'}).Count -eq $selected.Count){'three-across-double-column'}elseif($selected.Count -eq 2){'paired-double-column'}elseif($width -gt 95){'double-column'}else{'single-column'}
        $anchor=($blocks|Where-Object{[array]::IndexOf($blocks,$_) -lt $caption.block -and $_.text -match "图\s*$($caption.number)(?!\d)"}|ForEach-Object{[array]::IndexOf($blocks,$_) }|Select-Object -Last 1)
        $plan=[pscustomobject]@{number=$caption.number;caption=$caption.text;mode=$mode;anchorAfterBlock=if($null -eq $anchor){$caption.block-1}else{$anchor};captionBlock=$caption.block;assets=@($selected|ForEach-Object{$_.name})}
        $figurePlans.Add($plan)
        if($mode -ne 'single-column'){
            $widePoints.Add([pscustomobject]@{kind='figure';number=$caption.number;afterBlock=$plan.anchorAfterBlock;rule='panel-break-after-paragraph'})
            $references=@($blocks|Where-Object{[array]::IndexOf($blocks,$_) -lt $caption.block -and $_.role -eq 'body' -and $_.text -match "图\s*$($caption.number)(?!\d)"})
            if($references.Count -eq 0){$issues.Add([pscustomobject]@{code='WIDE_PANEL_ANCHOR';message="Figure $($caption.number) has no preceding body paragraph reference"})}
            else{$reference=$references[-1];$blockIndex=[array]::IndexOf($blocks,$reference);$wideBoundaries.Add([pscustomobject]@{kind='figure';number=$caption.number;paragraphText=[string]$reference.text;blockIndex=$blockIndex;objectNumber="block-$blockIndex";panelBreakAfterParagraph=$true})}
        }
    }
    $tablePlans=@();for($i=0;$i -lt $tables.Count;$i++){
        $number=$i+1;$rows=@($tables[$i].rows);$columns=if($rows.Count){@($rows[0]).Count}else{0};$mode=if($columns -ge 6){'double-column'}else{'single-column'}
        $captionBlocks=@($blocks|Where-Object{$_.role -eq 'table_caption' -and $_.text -match "^表\s*$number(?!\d)"})
        $captionBlock=if($captionBlocks.Count -eq 1){[array]::IndexOf($blocks,$captionBlocks[0])}else{$null}
        $tablePlans+=[pscustomobject]@{number=$number;mode=$mode;rows=$rows.Count;columns=$columns;continuedRisk=($rows.Count -gt 15);captionBlock=$captionBlock}
        if($mode -eq 'double-column'){
            $widePoints.Add([pscustomobject]@{kind='table';number=$number;rule='panel-break-after-paragraph'})
            $references=if($null -ne $captionBlock){@($blocks|Where-Object{[array]::IndexOf($blocks,$_) -lt $captionBlock -and $_.role -eq 'body' -and $_.text -match "表\s*$number(?!\d)"})}else{@()}
            if($references.Count -eq 0){$issues.Add([pscustomobject]@{code='WIDE_PANEL_ANCHOR';message="Table $number has no preceding body paragraph reference"})}
            else{$reference=$references[-1];$blockIndex=[array]::IndexOf($blocks,$reference);$wideBoundaries.Add([pscustomobject]@{kind='table';number=$number;paragraphText=[string]$reference.text;blockIndex=$blockIndex;objectNumber="block-$blockIndex";panelBreakAfterParagraph=$true})}
        }
    }
    $estimate=if($Task.PSObject.Properties['expectedPages'] -and [double]$Task.expectedPages -gt 0){[double]$Task.expectedPages}else{[math]::Ceiling(($bodyChars/1750)+($captions.Count*.45)+($tables.Count*.35)+1)}
    $pipeline=if($formulaCount -eq 0 -and $tables.Count -eq 0){'fast-graphics'}elseif($formulaCount -ge 10){'formula-dense'}else{'standard'}
    $issueArray=@($issues)
    [pscustomobject]@{taskId=$Task.taskId;author=$Task.author;generatedAt=(Get-Date).ToString('o');status=if($issues.Count){'needs_input'}else{'ready'};pipeline=$pipeline;issues=$issueArray;exceptionSummary=[ordered]@{needsInput=($issues.Count -gt 0);count=$issues.Count;codes=@($issueArray|ForEach-Object{$_.code}|Sort-Object -Unique);items=$issueArray};warnings=@($warnings);assets=@($assets);counts=[ordered]@{blocks=$blocks.Count;figures=$captions.Count;tables=$tables.Count;formulas=$formulaCount};layout=[ordered]@{estimatedPages=$estimate;articleStartsOn='left-even-page';figures=@($figurePlans);tables=@($tablePlans);crossColumnPoints=@($widePoints);widePanelBoundaries=@($wideBoundaries);notes=@('Plan is advisory until visual review','Keep cited paragraph intact around cross-column panels','Figure captions remain 5 pt from figures')}}
}

Export-ModuleMember -Function Read-JournalJson,Write-JournalJsonAtomic,New-JournalPreflightPlan
