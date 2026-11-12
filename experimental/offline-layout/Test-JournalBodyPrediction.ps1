#Requires -Version 7.0
param(
    [Parameter(Mandatory, ParameterSetName='Compare')][string]$WordDirectory,
    [Parameter(Mandatory, ParameterSetName='Compare')][string]$TitleReportPath,
    [Parameter(Mandatory, ParameterSetName='Compare')][string]$NativePath,
    [Parameter(Mandatory, ParameterSetName='Prepare')][string]$LogicalArticlePath,
    [Parameter(Mandatory)][string]$ReportPath,
    [double]$ColumnWidthMm = 85.5,
    [double]$FirstIndentPt = 22,
    [ValidateRange(0.5,1)][double]$PunctuationScale = 1,
    [ValidateRange(-2,2)][double]$WidthSlackMm = 0,
    [switch]$BalanceParagraph,
    [string]$CompositeIdmlPath,
    [ValidateRange(0,0.5)][double]$MixedScriptGapEm = 0,
    [ValidateRange(0,0.5)][double]$AdjacentPunctuationCompressionEm = 0,
    [switch]$MeasureSimpleRuns,
    [Parameter(ParameterSetName='Prepare')][string]$FormulaManifestPath,
    [switch]$MeasureItalicRuns,
    [Parameter(ParameterSetName='Prepare')][switch]$MeasureImporterMath,
    [Parameter(ParameterSetName='Prepare')][ValidateRange(-20,20)][int]$Tracking = 0,
    [Parameter(ParameterSetName='Prepare')][int[]]$TrackingSequences
)
$ErrorActionPreference = 'Stop'
if ($Tracking -and !$TrackingSequences.Count) { throw 'BODY_TRACKING_SEQUENCES_REQUIRED' }
Add-Type -AssemblyName PresentationCore,WindowsBase
$fontNames = @('SimSun', '汉仪中宋简', 'Times New Roman')
$typefaces = @{}
$boldFaces = @{}
$italicFaces = @{}
$available = [Windows.Media.Fonts]::SystemFontFamilies.Source
$measurementFonts = if ($MeasureImporterMath) { $fontNames + @('Cambria Math', 'Symbol') } else { $fontNames }
foreach ($name in $measurementFonts) {
    if ($name -notin $available) { throw "BODY_FONT_MISSING $name" }
    $typefaces[$name] = [Windows.Media.Typeface]::new($name)
    $boldFaces[$name] = [Windows.Media.Typeface]::new($typefaces[$name].FontFamily,
        [Windows.FontStyles]::Normal, [Windows.FontWeights]::Bold, [Windows.FontStretches]::Normal)
    if ($MeasureItalicRuns) {
        $italicFaces[$name] = [Windows.Media.Typeface]::new($typefaces[$name].FontFamily,
            [Windows.FontStyles]::Italic, [Windows.FontWeights]::Normal, [Windows.FontStretches]::Normal)
        $italicFaces["bold:$name"] = [Windows.Media.Typeface]::new($typefaces[$name].FontFamily,
            [Windows.FontStyles]::Italic, [Windows.FontWeights]::Bold, [Windows.FontStretches]::Normal)
    }
}
$culture = [Globalization.CultureInfo]::GetCultureInfo('zh-CN')
$widthCache = [Collections.Generic.Dictionary[string,double]]::new([StringComparer]::Ordinal)
$fontByCharacter = @{}
$formulaMarkerPattern = '⟦EQ-[0-9]+⟧'
$formulaWidths = [Collections.Generic.Dictionary[string,double]]::new([StringComparer]::Ordinal)
if ($FormulaManifestPath) {
    $manifest = Get-Content -LiteralPath $FormulaManifestPath -Raw | ConvertFrom-Json -Depth 100
    $entries = if ($manifest.formulas) { $manifest.formulas.entries } else { $manifest.entries }
    foreach ($entry in $entries) {
        $marker = [string]$entry.marker
        $width = [double]$entry.widthMm
        $height = [double]$entry.heightMm
        if ($marker -cnotmatch "^$formulaMarkerPattern$" -or [double]$entry.basePointSize -ne 10.5 -or
            ![double]::IsFinite($width) -or $width -le 0 -or ![double]::IsFinite($height) -or $height -le 0) {
            throw "BODY_FORMULA_MEASUREMENT_INVALID $marker"
        }
        if ($entry.inline -eq $false) { continue }
        if (!$formulaWidths.TryAdd($marker, $width)) { throw "BODY_FORMULA_MEASUREMENT_DUPLICATE $marker" }
    }
}
if ($CompositeIdmlPath) {
    $archive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $CompositeIdmlPath).Path)
    try {
        $composite = $null
        foreach ($part in 'Resources/Fonts.xml','Resources/Preferences.xml','designmap.xml') {
            $reader = [IO.StreamReader]::new($archive.GetEntry($part).Open())
            try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
            $composite = $xml.SelectSingleNode('//CompositeFont[@Self="CompositeFont/$ID/现 宋体-1"]')
            if ($composite) { break }
        }
        if (!$composite) { throw 'BODY_COMPOSITE_FONT_MISSING' }
        foreach ($entry in $composite.SelectNodes('./CompositeFontEntry[@CustomCharacters]')) {
            $font = $entry.SelectSingleNode('./Properties/AppliedFont').InnerText
            if (!$typefaces.ContainsKey($font)) { throw "BODY_COMPOSITE_FACE_UNAVAILABLE $font" }
            foreach ($character in $entry.GetAttribute('CustomCharacters').ToCharArray()) {
                $fontByCharacter[$character] = $font
            }
        }
    } finally { $archive.Dispose() }
}
function Key([string]$text) { $text.Normalize() -replace '\s', '' }
function Word-BodyKeys([string]$path) {
    $archive = [IO.Compression.ZipFile]::OpenRead($path)
    try {
        $reader = [IO.StreamReader]::new($archive.GetEntry('word/document.xml').Open())
        try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $archive.Dispose() }
    $ns = [Xml.XmlNamespaceManager]::new($xml.NameTable)
    $ns.AddNamespace('w', $xml.DocumentElement.NamespaceURI)
    $keys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($paragraph in $xml.SelectNodes('/w:document/w:body/w:p', $ns)) {
        [void]$keys.Add((Key (($paragraph.SelectNodes('.//w:t', $ns).InnerText) -join '')))
    }
    return ,$keys
}
function Width([string]$text, [bool]$bold = $false, [bool]$italic = $false) {
    $cacheKey = if ($italic) { "italic:${bold}:$text" } elseif ($bold) { "bold:$text" } else { $text }
    if (!$widthCache.ContainsKey($cacheKey)) {
        $font = if ($fontByCharacter.Count) {
                    if ($fontByCharacter.ContainsKey($text[0])) { $fontByCharacter[$text[0]] } else { $fontNames[0] }
                } elseif ($text -match '^[\u3000-\u303F\uFF00-\uFFEF]+$') { $fontNames[1] }
                elseif ($text -match '^[\u0000-\u024F]+$') { $fontNames[2] }
                else { $fontNames[0] }
        # Match fixSpecialGlyphs in import_word_article_to_indesign.jsx for these math symbols.
        $mathFace = if ($MeasureImporterMath) {
            if ($text -ceq '=') { 'Symbol' }
            elseif (!$italic -and $text -ceq '→') { 'Times New Roman' }
            elseif (!$italic -and $text -cmatch '^[≤≥]$') { 'SimSun' }
            elseif (!$italic -and $text -cmatch '^[\u2190-\u22FF\u27C0-\u27EF\u2980-\u2AFF×÷±′″]$') { 'Cambria Math' }
        }
        $face = if ($mathFace) { $typefaces[$mathFace] } elseif ($italic) {
            $italicFont = if ($text -match '^[\u0000-\u024F\u0370-\u03FF]+$') { $fontNames[2] } else { $font }
            if ($bold) { $italicFaces["bold:$italicFont"] } else { $italicFaces[$italicFont] }
        } elseif ($bold) { $boldFaces[$font] } else { $typefaces[$font] }
        $formatted = [Windows.Media.FormattedText]::new($text, $culture, [Windows.FlowDirection]::LeftToRight,
            $face, 10.5 * 96 / 72, [Windows.Media.Brushes]::Black, 1.0)
        $widthCache[$cacheKey] = $formatted.WidthIncludingTrailingWhitespace * 25.4 / 96
    }
    $widthCache[$cacheKey]
}
function Unit-Width([string]$unit) {
    $width = Width $unit
    if ($unit -match '^[，。；：、！？“”‘’（）《》【】]$') { $width *= $PunctuationScale }
    $width
}
function Mixed-Gap([string]$left, [string]$right) {
    if ($AdjacentPunctuationCompressionEm -and $left -match '^[，。；：、！？）》】」』]$' -and
        $right -match '^[，。；：、！？（）《》【】「」『』“”‘’]$') {
        return -$AdjacentPunctuationCompressionEm * 10.5 * 25.4 / 72
    }
    if ($MixedScriptGapEm -and (
        ($left -match '[\p{IsCJKUnifiedIdeographs}]$' -and $right -match '^[A-Za-z0-9]') -or
        ($left -match '[A-Za-z0-9]$' -and $right -match '^[\p{IsCJKUnifiedIdeographs}]')
    )) { return $MixedScriptGapEm * 10.5 * 25.4 / 72 }
    0.0
}
function Break-Balanced($units, $widths, [double]$trackingMm = 0) {
    $length = $units.Count
    $prefix = [double[]]::new($length + 1)
    $score = [double[]]::new($length + 1)
    $next = [int[]]::new($length + 1)
    $gaps = [double[]]::new($length)
    for ($i = 0; $i -lt $length; $i++) {
        if ($i) { $gaps[$i] = (Mixed-Gap $units[$i - 1] $units[$i]) + $trackingMm }
        $prefix[$i + 1] = $prefix[$i] + $widths[$i] + $gaps[$i]
    }
    for ($start = $length - 1; $start -ge 0; $start--) {
        $score[$start] = [double]::PositiveInfinity
        $limit = $ColumnWidthMm + $WidthSlackMm
        if (!$start) { $limit -= $FirstIndentPt * 25.4 / 72 }
        for ($end = $start + 1; $end -le $length; $end++) {
            $span = $prefix[$end] - $prefix[$start] - $gaps[$start]
            if ($units[$end - 1] -match '^\s+$') { $span -= $prefix[$end] - $prefix[$end - 1] }
            if ($span -gt $limit + 0.6) { break }
            if ($end -lt $length -and ($units[$end] -match '^[\s，。；：、！？）》】」』]' -or
                $units[$end - 1] -match '^[（《【「『]$')) { continue }
            $penalty = if ($end -eq $length) { 0 } else { 1 + [math]::Pow(($span - $limit) / 3.7, 2) }
            if ($span -gt $limit) { $penalty += [math]::Pow(($span - $limit) * 3, 2) }
            $candidate = $score[$end] + $penalty
            if ($candidate -lt $score[$start]) { $score[$start] = $candidate; $next[$start] = $end }
        }
    }
    if (!$next[0]) { return }
    for ($start = 0; $start -lt $length; $start = $end) {
        $end = $next[$start]
        ($units[$start..($end - 1)] -join '').Trim()
    }
}
function Body-Units([string]$text) {
    [regex]::Matches($text, $formulaMarkerPattern + '|\[\d+(?:[\s,，、–—-]+\d+)*\]|[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*|.')
}
function Expand-ImporterEquals([string]$text, $runs) {
    $equals = [regex]::Matches($text, '[=＝]')
    $positionMap = [int[]]::new($text.Length + 1)
    $shift = 0
    $nextEquals = 0
    $insertedRuns = @(for ($i = 0; $i -lt $text.Length; $i++) {
        $positionMap[$i] = $i + $shift
        if ($nextEquals -lt $equals.Count -and $equals[$nextEquals].Index -eq $i) {
            @{ start = $i + $shift; end = $i + $shift + 1; position = 'subscript'; importerSpace = $true }
            @{ start = $i + $shift + 2; end = $i + $shift + 3; position = 'subscript'; importerSpace = $true }
            $positionMap[$i]++
            $shift += 2
            $nextEquals++
        }
    })
    $positionMap[$text.Length] = $text.Length + $shift
    $mappedRuns = @(foreach ($run in $runs) {
        [pscustomobject]@{ start = $positionMap[$run.start]; end = $positionMap[$run.end]
            bold = $run.bold; italic = $run.italic; position = $run.position }
    })
    @{ text = $text -creplace '[=＝]', ' = '; runs = $mappedRuns + @($insertedRuns | ForEach-Object { [pscustomobject]$_ }) }
}
function Styled-Width($token, $runs) {
    if ($formulaWidths.ContainsKey($token.Value)) { return $formulaWidths[$token.Value] }
    if (!$runs.Count) { return (Unit-Width $token.Value) }
    $end = $token.Index + $token.Length
    $overlap = @($runs | Where-Object { $_.start -lt $end -and $_.end -gt $token.Index })
    if (!$overlap.Count) { return (Unit-Width $token.Value) }
    $points = @($token.Index; $end; foreach ($run in $overlap) {
        [math]::Max($token.Index, [int]$run.start)
        [math]::Min($end, [int]$run.end)
    }) | Sort-Object -Unique
    $total = 0.0
    for ($i = 0; $i -lt $points.Count - 1; $i++) {
        $start = $points[$i]
        $active = @($overlap | Where-Object { $_.start -le $start -and $_.end -gt $start })
        if (@($active | Where-Object importerSpace -eq $true).Count) {
            $total += (Width ' ') * 0.583
            continue
        }
        $bold = @($active | Where-Object bold -eq $true).Count -gt 0
        $italic = $MeasureItalicRuns -and @($active | Where-Object italic -eq $true).Count -gt 0
        $scale = if (@($active | Where-Object position -in 'superscript','subscript').Count) { 0.583 } else { 1 }
        $segment = $token.Value.Substring($start - $token.Index, $points[$i + 1] - $start)
        $total += (Width $segment $bold $italic) * $scale
    }
    $total
}
function Body-LineWidth([string]$text) {
    $width = 0.0; $previous = ''
    foreach ($unit in ((Body-Units $text).Value)) {
        $width += (Unit-Width $unit) + (Mixed-Gap $previous $unit)
        $previous = $unit
    }
    $width
}
function Break-Body([string]$text, $runs, [int]$trackingUnits = 0) {
    $tokens = @(Body-Units $text)
    $units = @($tokens | ForEach-Object Value)
    $trackingMm = $trackingUnits / 1000 * 10.5 * 25.4 / 72
    $widths = @(foreach ($token in $tokens) {
        $width = Styled-Width $token $runs
        if ($trackingMm -and !$formulaWidths.ContainsKey($token.Value)) {
            $width += ($token.Length - 1) * $trackingMm
        }
        $width
    })
    if ($BalanceParagraph) {
        $balanced = @(Break-Balanced $units $widths $trackingMm)
        if ($balanced.Count) { return $balanced }
    }
    $line = ''; $used = 0.0; $limit = $ColumnWidthMm + $WidthSlackMm - $FirstIndentPt * 25.4 / 72
    $previous = ''
    for ($i = 0; $i -lt $units.Count; $i++) {
        $unit = $units[$i]
        $width = $widths[$i]
        $gap = Mixed-Gap $previous $unit
        if ($line) { $gap += $trackingMm }
        if ($line -and $used + $width + $gap -gt $limit -and $unit -notmatch '^[，。；：、！？）》】」』]$') {
            $line.Trim()
            $line = ''; $used = 0.0; $limit = $ColumnWidthMm + $WidthSlackMm
            $previous = ''; $gap = 0.0
            if ($unit -match '^\s+$') { continue }
        }
        $line += $unit
        $used += $width + $gap
        $previous = $unit
    }
    if ($line.Trim()) { $line.Trim() }
}
function Write-BodyReport($result) {
    $stream = [IO.File]::Open([IO.Path]::GetFullPath($ReportPath), [IO.FileMode]::CreateNew)
    try {
        $writer = [IO.StreamWriter]::new($stream)
        try { $writer.Write(($result | ConvertTo-Json -Depth 20)) } finally { $writer.Dispose() }
    } finally { $stream.Dispose() }
}
function Has-UnsupportedFormatting($block) {
    if ($block.text -match '[\uFFFC\u0016\t]|\{\{(?:EQ|FORMULA)') { return $true }
    if (!$FormulaManifestPath -and $block.text -cmatch $formulaMarkerPattern) { return $true }
    if (!$MeasureSimpleRuns) { return $block.runs.Count -or $block.text -match '\[\d' }
    $supported = @('start', 'end', 'bold', 'position')
    if ($MeasureItalicRuns) { $supported += 'italic' }
    foreach ($run in $block.runs) {
        if (@($run.PSObject.Properties.Name | Where-Object { $_ -notin $supported }).Count -or
            ($run.position -and $run.position -notin 'superscript','subscript')) { return $true }
    }
    $false
}
if ($LogicalArticlePath) {
    $source = Get-Content -LiteralPath $LogicalArticlePath -Raw | ConvertFrom-Json -Depth 100
    $blocks = @(foreach ($block in $source.blocks) {
        $oversizeFormula = $false
        if ($FormulaManifestPath -and $block.role -eq 'body') {
            foreach ($marker in [regex]::Matches([string]$block.text, $formulaMarkerPattern)) {
                if (!$formulaWidths.ContainsKey($marker.Value)) {
                    throw "BODY_FORMULA_MEASUREMENT_MISSING seq=$($block.seq) $($marker.Value)"
                }
                if ($formulaWidths[$marker.Value] -gt $ColumnWidthMm) { $oversizeFormula = $true }
            }
        }
        $status = if ($block.role -ne 'body') { 'requires-role-model' }
            elseif ($oversizeFormula) { 'requires-formula-break-model' }
            elseif (Has-UnsupportedFormatting $block) { 'requires-inline-format-model' }
            elseif (!$block.text.Trim()) { 'empty' }
            else { 'predicted' }
        $lines = @(if ($status -eq 'predicted') {
            $blockTracking = if ($block.seq -in $TrackingSequences) { $Tracking } else { 0 }
            if ($MeasureImporterMath -and $block.text -cmatch '[=＝]') {
                $projected = Expand-ImporterEquals $block.text $block.runs
                Break-Body $projected.text $projected.runs $blockTracking
            } else { Break-Body $block.text $block.runs $blockTracking }
        })
        $row = [ordered]@{ seq = $block.seq; role = $block.role; status = $status
            lines = $lines; nominalLeadingMm = if ($lines.Count) { $lines.Count * 15 * 25.4 / 72 } else { $null } }
        if ($FormulaManifestPath -and $lines.Count) { $row.heightStatus = 'requires-native-height-model' }
        $row
    })
    $profile = [ordered]@{ widthMm = $ColumnWidthMm; firstIndentPt = $FirstIndentPt
        fonts = $fontNames; pointSize = 10.5; widthSlackMm = $WidthSlackMm; mixedScriptGapEm = $MixedScriptGapEm }
    if ($MeasureItalicRuns) { $profile.measureItalicRuns = $true }
    if ($MeasureImporterMath) { $profile.measureImporterMath = $true }
    if ($Tracking) {
        $profile.tracking = $Tracking
        $profile.trackingSequences = $TrackingSequences
        $profile.trackingBasis = 'increment in thousandths of 10.5 pt em between modeled characters; no internal anchor tracking'
    }
    if ($FormulaManifestPath) {
        $profile.formulaManifest = (Resolve-Path -LiteralPath $FormulaManifestPath).Path
        $profile.formulaManifestSha256 = (Get-FileHash -LiteralPath $FormulaManifestPath).Hash
        $profile.formulaWidthBasis = 'manifest geometry at 10.5 pt'
        $profile.balanceParagraph = [bool]$BalanceParagraph
        $profile.measureSimpleRuns = [bool]$MeasureSimpleRuns
        $profile.punctuationScale = $PunctuationScale
        $profile.adjacentPunctuationCompressionEm = $AdjacentPunctuationCompressionEm
        if ($CompositeIdmlPath) {
            $profile.compositeIdml = (Resolve-Path -LiteralPath $CompositeIdmlPath).Path
            $profile.compositeIdmlSha256 = (Get-FileHash -LiteralPath $CompositeIdmlPath).Hash
        }
    }
    $result = [ordered]@{
        status = 'partial-planning-inputs'; source = (Resolve-Path -LiteralPath $LogicalArticlePath).Path
        sourceSha256 = (Get-FileHash -LiteralPath $LogicalArticlePath).Hash
        profile = $profile
        blocks = $blocks
    }
    if ($FormulaManifestPath) {
        $result.limitations = @('Line breaks are a WPF estimate of the journal composition.',
            'Nominal leading is the line count multiplied by 15 pt. Actual occupied height requires a native height model.',
            'Formula height, anchor position, existing per-range tracking and page or column assignment are outside this estimate.')
    }
    Write-BodyReport $result
    $blocks | Group-Object { $_.status } | Select-Object Count,Name
    return
}
$titles = Get-Content -LiteralPath $TitleReportPath -Raw | ConvertFrom-Json -Depth 100
$native = Get-Content -LiteralPath $NativePath -Raw | ConvertFrom-Json -Depth 100
$cached = @{}
foreach ($file in (Get-ChildItem -LiteralPath $WordDirectory -Recurse -File -Filter '*.json')) {
    if (!$cached.ContainsKey($file.BaseName)) { $cached[$file.BaseName] = @() }
    $cached[$file.BaseName] += $file.FullName
}
$reports = @(for ($index = 0; $index -lt $titles.articles.Count; $index++) {
    $title = $titles.articles[$index]
    $start = @($native.pages | Where-Object name -ceq $title.page)
    $end = if ($index + 1 -lt $titles.articles.Count) {
        ($native.pages | Where-Object name -ceq $titles.articles[$index + 1].page | Select-Object -First 1).index - 1
    } else { $native.pages.Count - 1 }
    $stats = [ordered]@{ page = $title.page; title = $title.title; wordPath = $title.wordPath
        sample = if ($index % 5 -eq 4) { 'holdout' } else { 'calibration' }
        eligible = 0; exact = 0; wrongLineCount = 0; wrongBreak = 0; changedOrMissing = 0
        unsupportedFormat = 0; sourceTextNotVerified = 0; firstDifference = $null; status = 'no-source'
        paragraphResults = [Collections.Generic.List[object]]::new() }
    if (!$title.wordPath -or $start.Count -ne 1) { $stats; continue }
    $paths = @($cached[[IO.Path]::GetFileNameWithoutExtension($title.wordPath)])
    $adjacent = [IO.Path]::ChangeExtension($title.wordPath, '.json')
    if ($adjacent -in $paths) { $paths = @($adjacent) }
    if ($paths.Count -ne 1 -or !$paths[0]) { $stats; continue }
    $source = Get-Content -LiteralPath $paths[0] -Raw | ConvertFrom-Json -Depth 100
    if ([IO.Path]::GetFileName($source.source) -cne [IO.Path]::GetFileName($title.wordPath)) { $stats; continue }
    $sourceKeys = if ([IO.Path]::GetExtension($title.wordPath) -ieq '.docx') { ,(Word-BodyKeys $title.wordPath) }
    $stats.wordIdentity = if ($null -ne $sourceKeys) { 'docx-paragraph-text' } else { 'legacy-extraction-only' }
    $stats.status = 'compared'
    $stats.wordExtraction = $paths[0]
    $paragraphs = @{}
    foreach ($page in ($native.pages | Where-Object { $_.index -ge $start[0].index -and $_.index -le $end })) {
        foreach ($frame in $page.frames) {
            foreach ($line in $frame.lines) {
                if ($line[3] -notin '正文_wrd_1','正文','段落样式1','内文') { continue }
                $id = "$($frame.storyId):$($line[2])"
                if (!$paragraphs.ContainsKey($id)) { $paragraphs[$id] = [Collections.Generic.List[object]]::new() }
                $paragraphs[$id].Add($line)
            }
        }
    }
    $actual = @{}
    foreach ($paragraph in $paragraphs.Values) {
        $lines = @($paragraph | Sort-Object { $_[0] } | ForEach-Object { $_[9].Trim() })
        $key = Key ($lines -join '')
        if (!$key) { continue }
        if (!$actual.ContainsKey($key)) { $actual[$key] = @() }
        $actual[$key] += ,$lines
    }
    foreach ($block in $source.blocks | Where-Object role -eq 'body') {
        $text = [string]$block.text
        if (!$text.Trim()) { continue }
        if (Has-UnsupportedFormatting $block) {
            $stats.unsupportedFormat++; continue
        }
        $key = Key $text
        if ($null -ne $sourceKeys -and !$sourceKeys.Contains($key)) { $stats.sourceTextNotVerified++; continue }
        if (!$actual.ContainsKey($key) -or $actual[$key].Count -ne 1) { $stats.changedOrMissing++; continue }
        $stats.eligible++
        $observed = @($actual[$key][0])
        $predicted = @(Break-Body $text $block.runs)
        $predictedKey = ($predicted | ForEach-Object { Key $_ }) -join '|'
        $observedKey = ($observed | ForEach-Object { Key $_ }) -join '|'
        $stats.paragraphResults.Add([ordered]@{ seq = $block.seq; predictedLines = $predicted.Count
            observedLines = $observed.Count; exact = $predictedKey -ceq $observedKey
            predictedLastLineMm = [math]::Round((Body-LineWidth $predicted[-1]), 4)
            mixed = $text -match '[A-Za-z0-9]' })
        if ($predictedKey -ceq $observedKey) {
            $stats.exact++; continue
        }
        $kind = if ($predicted.Count -ne $observed.Count) { 'wrongLineCount' } else { 'wrongBreak' }
        $stats[$kind]++
        if (!$stats.firstDifference) {
            $stats.firstDifference = [ordered]@{ sequence = $block.seq; kind = $kind
                predictedLines = $predicted; actualLines = $observed }
        }
    }
    $stats
})
$result = [ordered]@{ status = 'body-baseline'; widthMm = $ColumnWidthMm; firstIndentPt = $FirstIndentPt
    punctuationScale = $PunctuationScale; widthSlackMm = $WidthSlackMm
    balanceParagraph = [bool]$BalanceParagraph
    compositeCharacterCount = $fontByCharacter.Count
    mixedScriptGapEm = $MixedScriptGapEm
    adjacentPunctuationCompressionEm = $AdjacentPunctuationCompressionEm
    measuredSimpleRuns = [bool]$MeasureSimpleRuns
    fonts = $fontNames; pointSize = 10.5; articles = $reports
    limitations = @('Uses existing Word extraction for roles; DOCX paragraph text checked against the source',
        'Legacy DOC only checked against its cached extraction', 'Only unchanged paragraphs with a unique native match',
        'Unsupported inline formatting and formula spans excluded', 'No page or column assignment predicted') }
if ($MeasureItalicRuns) { $result.measuredItalicRuns = $true }
Write-BodyReport $result
[pscustomobject]@{
    articles = @($reports | Where-Object { $_.status -eq 'compared' }).Count
    eligible = ($reports | ForEach-Object eligible | Measure-Object -Sum).Sum
    exact = ($reports | ForEach-Object exact | Measure-Object -Sum).Sum
    wrongLineCount = ($reports | ForEach-Object wrongLineCount | Measure-Object -Sum).Sum
    wrongBreak = ($reports | ForEach-Object wrongBreak | Measure-Object -Sum).Sum
}
