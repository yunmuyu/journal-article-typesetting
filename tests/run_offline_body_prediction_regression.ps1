#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationCore,WindowsBase

function Measure-TestText([string]$value, $style, [string]$font = 'Times New Roman') {
    $face = [Windows.Media.Typeface]::new([Windows.Media.FontFamily]::new($font),
        $style, [Windows.FontWeights]::Normal, [Windows.FontStretches]::Normal)
    $text = [Windows.Media.FormattedText]::new($value, [Globalization.CultureInfo]::GetCultureInfo('zh-CN'),
        [Windows.FlowDirection]::LeftToRight, $face, 14, [Windows.Media.Brushes]::Black, 1.0)
    $text.WidthIncludingTrailingWhitespace * 25.4 / 96
}

$temp = New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) "journal-body-$([guid]::NewGuid())")
try {
    $source = Join-Path $temp.FullName 'logical.json'
    $manifest = Join-Path $temp.FullName 'job.json'
    $predictor = Join-Path $PSScriptRoot '../experimental/offline-layout/Test-JournalBodyPrediction.ps1'
    $marker = '⟦EQ-001⟧'
    $italics = 'ffffffff'
    $formulaWidth = 12
    $regularWidth = Measure-TestText $italics ([Windows.FontStyles]::Normal)
    $italicWidth = Measure-TestText $italics ([Windows.FontStyles]::Italic)
    if ($regularWidth -eq $italicWidth) { throw 'TEST_ITALIC_WIDTHS_INDISTINGUISHABLE' }
    $column = $formulaWidth + ($regularWidth + $italicWidth) / 2
    $entries = @(@{ marker = $marker; widthMm = $formulaWidth; heightMm = 4; basePointSize = 10.5; inline = $true })
    @{ formulas = @{ entries = $entries } } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifest

    @{
        blocks = @(
            @{ seq = 1; role = 'body'; text = "中中中中${marker}"; runs = @() }
            @{ seq = 2; role = 'body'; text = "$marker$italics"; runs = @() }
            @{ seq = 3; role = 'body'; text = "$marker$italics"
                runs = @(@{ start = $marker.Length; end = $marker.Length + $italics.Length; italic = $true }) }
            @{ seq = 4; role = 'body'; text = 'a＝b=c'; runs = @() }
            @{ seq = 5; role = 'body'; text = 'a∞'; runs = @() }
            @{ seq = 6; role = 'body'; text = '中文'; runs = @() }
            @{ seq = 7; role = 'body'; text = '中文'; runs = @() }
            @{ seq = 8; role = 'body'; text = 'W'; runs = @() }
            @{ seq = 9; role = 'body'; text = 'w中'; runs = @() }
        )
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $source
    $arguments = @{ LogicalArticlePath = $source; FirstIndentPt = 0; ColumnWidthMm = $column }
    $report = Join-Path $temp.FullName 'prediction.json'
    & $predictor @arguments -ReportPath $report -FormulaManifestPath $manifest -MeasureSimpleRuns -MeasureItalicRuns | Out-Null
    $blocks = (Get-Content -LiteralPath $report -Raw | ConvertFrom-Json).blocks
    if (($blocks[0].lines -join '|') -cne "中中中中|${marker}") { throw 'FORMULA_ATOMIC_WIDTH' }
    foreach ($item in @(@{ Block = $blocks[1]; Width = $regularWidth }, @{ Block = $blocks[2]; Width = $italicWidth })) {
        $expected = if ($formulaWidth + $item.Width -gt $column) { "$marker|$italics" } else { "$marker$italics" }
        if ($item.Block.status -ne 'predicted' -or ($item.Block.lines -join '|') -cne $expected) {
            throw 'FORMULA_ITALIC_SOURCE_OFFSETS'
        }
    }

    $missingReport = Join-Path $temp.FullName 'no-manifest.json'
    & $predictor @arguments -ReportPath $missingReport -MeasureSimpleRuns | Out-Null
    $missing = (Get-Content -LiteralPath $missingReport -Raw | ConvertFrom-Json).blocks[0]
    if ($missing.status -eq 'predicted' -or $missing.lines.Count) { throw 'FORMULA_WITHOUT_MANIFEST_PREDICTED' }

    $importerReport = Join-Path $temp.FullName 'importer-math.json'
    & $predictor -LogicalArticlePath $source -ReportPath $importerReport -MeasureImporterMath | Out-Null
    $importerMath = (Get-Content -LiteralPath $importerReport -Raw | ConvertFrom-Json).blocks[3]
    if (($importerMath.lines -join '|') -cne 'a = b = c') { throw 'IMPORTER_EQUALS_PROJECTION' }

    $symbolReport = Join-Path $temp.FullName 'math-symbol.json'
    $normal = [Windows.FontStyles]::Normal
    $simsunWidth = Measure-TestText '∞' $normal 'SimSun'
    $cambriaWidth = Measure-TestText '∞' $normal 'Cambria Math'
    if ($cambriaWidth -ge $simsunWidth) { throw 'TEST_MATH_WIDTHS_INDISTINGUISHABLE' }
    $symbolColumn = (Measure-TestText 'a' $normal) + ($cambriaWidth + $simsunWidth) / 2
    & $predictor -LogicalArticlePath $source -ReportPath $symbolReport -ColumnWidthMm $symbolColumn -FirstIndentPt 0 -MeasureImporterMath | Out-Null
    $symbol = (Get-Content -LiteralPath $symbolReport -Raw | ConvertFrom-Json).blocks[4]
    if (($symbol.lines -join '|') -cne 'a∞') { throw 'IMPORTER_MATH_FACE_WIDTH' }

    $trackingReport = Join-Path $temp.FullName 'tracking.json'
    $trackingColumn = (Measure-TestText '中' $normal 'SimSun') + (Measure-TestText '文' $normal 'SimSun') - 0.05
    & $predictor -LogicalArticlePath $source -ReportPath $trackingReport -ColumnWidthMm $trackingColumn -FirstIndentPt 0 -Tracking -20 -TrackingSequences 6 | Out-Null
    $trackingBlocks = (Get-Content -LiteralPath $trackingReport -Raw | ConvertFrom-Json).blocks
    if (($trackingBlocks[5].lines -join '|') -cne '中文' -or ($trackingBlocks[6].lines -join '|') -cne '中|文') {
        throw 'TRACKING_SEQUENCE_SCOPE_AND_WIDTH'
    }

    $caseReport = Join-Path $temp.FullName 'case-sensitive-width.json'
    $caseColumn = (Measure-TestText '中' $normal 'SimSun') +
        ((Measure-TestText 'W' $normal) + (Measure-TestText 'w' $normal)) / 2
    & $predictor -LogicalArticlePath $source -ReportPath $caseReport -ColumnWidthMm $caseColumn -FirstIndentPt 0 | Out-Null
    $caseBlock = (Get-Content -LiteralPath $caseReport -Raw | ConvertFrom-Json).blocks[8]
    if (($caseBlock.lines -join '|') -cne 'w中') { throw 'GLYPH_CACHE_CASE_COLLISION' }

    $entries[0].widthMm = 100
    @{ formulas = @{ entries = $entries } } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifest
    $oversizeReport = Join-Path $temp.FullName 'oversize-formula.json'
    & $predictor -LogicalArticlePath $source -ReportPath $oversizeReport -FormulaManifestPath $manifest -BalanceParagraph | Out-Null
    $oversize = (Get-Content -LiteralPath $oversizeReport -Raw | ConvertFrom-Json).blocks[0]
    if ($oversize.status -ne 'requires-formula-break-model' -or $oversize.lines.Count -or
        $null -ne $oversize.nominalLeadingMm) { throw 'OVERSIZE_FORMULA_PREDICTED' }

    $entries[0].marker = '⟦EQ-002⟧'
    @{ formulas = @{ entries = $entries } } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifest
    $failureReport = Join-Path $temp.FullName 'missing-formula.json'
    try {
        & $predictor @arguments -ReportPath $failureReport -FormulaManifestPath $manifest | Out-Null
        throw 'FORMULA_MISSING_ENTRY_ACCEPTED'
    } catch {
        if ($_.Exception.Message -notmatch '^BODY_FORMULA_MEASUREMENT_MISSING') { throw }
    }
    if (Test-Path -LiteralPath $failureReport) { throw 'FORMULA_MISSING_ENTRY_REPORT_CREATED' }
    'PASS inline formula width, atomic marker, oversized formula, italic source offsets, missing measurement, importer math, scoped tracking and case-sensitive widths'
} finally {
    Get-ChildItem -LiteralPath $temp.FullName -File | Remove-Item
    Remove-Item -LiteralPath $temp.FullName
}
