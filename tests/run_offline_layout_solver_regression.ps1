#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$module = Join-Path $root 'experimental/offline-layout'
$examples = Join-Path $root 'examples/offline-layout'
$solver = Join-Path $module 'Find-MeasuredPageWindow.ps1'
$reviewer = Join-Path $module 'Test-JournalLayoutRobustness.ps1'
$selector = Join-Path $module 'Select-JournalOneShotLayout.ps1'
$nominalPath = Join-Path $examples 'synthetic-window.json'
$riskPath = Join-Path $examples 'synthetic-window-overflow-risk.json'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('offline-layout-' + [guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($temp)

function Assert-Equal($Actual, $Expected) {
    if ($Actual -cne $Expected) { throw "Expected [$Expected], got [$Actual]" }
}

function Assert-Throws([scriptblock]$Action, [string]$Code) {
    try { & $Action | Out-Null } catch {
        if ($_.Exception.Message -notlike "$Code*") { throw }
        return
    }
    throw "Expected exception $Code"
}

function New-Window {
    Get-Content -LiteralPath $nominalPath -Raw | ConvertFrom-Json
}

function Write-Window($Window, [string]$Name) {
    $path = Join-Path $temp "$Name.json"
    $Window | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding utf8
    return $path
}

try {
    $reportPath = Join-Path $temp 'report.json'
    Assert-Equal (& $selector -CandidatePaths $riskPath,$nominalPath -ReportPath $reportPath) 'one-offline-plan-selected'
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    Assert-Equal $report.adobeCalls 0
    Assert-Equal $report.selected.sha256 (Get-FileHash -LiteralPath $nominalPath).Hash
    Assert-Equal ($report.selected.plan.placements.endIndex -join ',') '110,120,130,140,150,160,170'
    Assert-Equal $report.candidates[0].status 'measurement-risk'
    Assert-Equal (($report.candidates[0].review.issues | Where-Object code -eq 'MAY_OVERFLOW').slot -join ',') '3,4'
    Assert-Equal $report.selected.review.slots[3].minimumCapacityMm 24

    $riskReport = Join-Path $temp 'risk-report.json'
    Assert-Equal (& $selector -CandidatePaths $riskPath -ReportPath $riskReport) 'no-robust-offline-plan'
    $riskResult = Get-Content -LiteralPath $riskReport -Raw | ConvertFrom-Json
    Assert-Equal ($null -eq $riskResult.selected) $true
    Assert-Equal $riskResult.candidates.Count 1

    $other = New-Window
    $other.sourceIdentity = 'SYNTHETIC-DEMO'
    $otherPath = Write-Window $other 'other-source'
    $badReport = Join-Path $temp 'mismatch-report.json'
    Assert-Throws { & $selector -CandidatePaths $nominalPath,$otherPath -ReportPath $badReport } 'LAYOUT_CANDIDATES_REQUIRE_SAME_SOURCE_RANGE'
    Assert-Equal (Test-Path -LiteralPath $badReport) $false

    $other.sourceIdentity = 'synthetic-' + [char]0x00AD + 'demo'
    $otherPath = Write-Window $other 'other-opaque-source'
    Assert-Throws { & $selector -CandidatePaths $nominalPath,$otherPath -ReportPath $badReport } 'LAYOUT_CANDIDATES_REQUIRE_SAME_SOURCE_RANGE'
    Assert-Equal (Test-Path -LiteralPath $badReport) $false

    $paired = @{
        version = 1; sourceIdentity = 'synthetic-pair-close'; startIndex = 100; endIndex = 102
        blocks = @(
            @{ startIndex = 100; endIndex = 101; kind = 'body'; advanceMm = 20; compressMm = 5; canBreakAfter = $true; errorBelowMm = 0; errorAboveMm = 0 }
            @{ startIndex = 101; endIndex = 102; kind = 'body'; advanceMm = 15; errorBelowMm = 0; errorAboveMm = 0 }
        )
        slots = @(
            @{ page = 2; kind = 'tail-left'; capacityMm = 20; maxBlankMm = 1; closePage = $true }
            @{ page = 2; kind = 'tail-right'; capacityMm = 20; maxBlankMm = 1 }
        )
    }
    $pairedPath = Write-Window $paired 'paired-close-page-gap'
    Assert-Equal (& $solver -MeasurementPath $pairedPath).status 'no-candidate-in-window'
    $paired.blocks[1].advanceMm = 19
    $pairedPath = Write-Window $paired 'paired-close-page-ok'
    $pairedPlan = & $solver -MeasurementPath $pairedPath
    Assert-Equal $pairedPlan.status 'ready-for-native-check'
    Assert-Equal ([math]::Round($pairedPlan.placements[0].blankMm, 4)) 0.9
    $paired.slots[0].closePage = $false
    $paired.slots[1].closePage = $true
    $paired.slots[1].maxBlankMm = 0.5
    $pairedPath = Write-Window $paired 'paired-right-close-page-gap'
    Assert-Equal (& $solver -MeasurementPath $pairedPath).status 'no-candidate-in-window'

    $gap = New-Window
    $gap.blocks[3].errorBelowMm = 1.5
    $gapPath = Write-Window $gap 'gap-risk'
    $gapPlan = & $solver -MeasurementPath $gapPath
    $gapReview = & $reviewer -MeasurementPath $gapPath -Plan $gapPlan | ConvertFrom-Json
    Assert-Equal $gapReview.status 'measurement-risk'
    Assert-Equal $gapReview.issues[0].code 'MAY_LEAVE_GAP'

    $incomplete = New-Window
    $incomplete.blocks[4].startIndex = 141
    $incompletePath = Write-Window $incomplete 'incomplete-blocks'
    Assert-Throws { & $solver -MeasurementPath $incompletePath } 'PAGE_WINDOW_BLOCK_INVALID'
    $badPlan = & $solver -MeasurementPath $nominalPath
    $badPlan.placements[-1].endIndex = 169
    Assert-Throws { & $reviewer -MeasurementPath $nominalPath -Plan $badPlan } 'LAYOUT_SLOT_ENDPOINT'

    $badHeight = & $solver -MeasurementPath $nominalPath
    $badHeight.placements[3].occupiedMm = 23.5
    $badHeightReview = & $reviewer -MeasurementPath $nominalPath -Plan $badHeight | ConvertFrom-Json
    Assert-Equal $badHeightReview.issues[0].code 'ADJUSTMENT_OUT_OF_RANGE'

    foreach ($delta in 0.09,0.1,0.11) {
        $tail = New-Window
        $tail.blocks[-2].errorBelowMm = 0
        $tail.blocks[-2].errorAboveMm = 0
        $tail.blocks[-1].errorBelowMm = 0
        $tail.blocks[-1].errorAboveMm = 0
        $tail.blocks[-1].advanceMm = 15 + $delta
        $tailPath = Write-Window $tail "tail-$delta"
        $tailPlan = & $solver -MeasurementPath $tailPath
        if ($delta -le 0.1) {
            Assert-Equal $tailPlan.status 'ready-for-native-check'
            $tailReview = & $reviewer -MeasurementPath $tailPath -Plan $tailPlan | ConvertFrom-Json
            Assert-Equal $tailReview.status 'robust-under-supplied-bounds'
        } else {
            Assert-Equal $tailPlan.status 'no-candidate-in-window'
            Assert-Equal $tailPlan.placements.Count 0
        }
    }
    $uncertainTail = New-Window
    $uncertainTail.blocks[-1].errorAboveMm = 0.03005
    $uncertainPath = Write-Window $uncertainTail 'uncertain-tail'
    $uncertainPlan = & $solver -MeasurementPath $uncertainPath
    $uncertainReview = & $reviewer -MeasurementPath $uncertainPath -Plan $uncertainPlan | ConvertFrom-Json
    Assert-Equal $uncertainReview.issues[0].code 'MAY_MISS_BOTTOM_ALIGNMENT'

    $spanEnd = New-Window
    $spanEnd.blocks = $spanEnd.blocks[0..2]
    $spanEnd.slots = $spanEnd.slots[0..2]
    $spanEnd.endIndex = 130
    $spanEndPath = Write-Window $spanEnd 'span-at-end'
    $spanEndPlan = & $solver -MeasurementPath $spanEndPath
    Assert-Equal $spanEndPlan.status 'ready-for-native-check'
    Assert-Equal $spanEndPlan.placements[-1].endIndex 130

    $invalid = New-Window
    $invalid.slots[0].requiredEndIndex = 110
    $invalidPath = Write-Window $invalid 'source-index-used-as-offset'
    Assert-Throws { & $solver -MeasurementPath $invalidPath } 'PAGE_WINDOW_SLOT_INVALID'
    $invalid = New-Window
    $invalid.slots[3].page = 3
    $invalidPath = Write-Window $invalid 'lower-band-on-wrong-page'
    Assert-Throws { & $solver -MeasurementPath $invalidPath } 'PAGE_WINDOW_LOWER_BAND_WITHOUT_SPAN'
    $invalid = New-Window
    $invalid.blocks[0].advanceMm = '16'
    $invalidPath = Write-Window $invalid 'numeric-string'
    Assert-Throws { & $solver -MeasurementPath $invalidPath } 'PAGE_WINDOW_BLOCK_INVALID'
    $invalid = New-Window
    $invalid.blocks[0].PSObject.Properties.Remove('errorAboveMm')
    $invalidPath = Write-Window $invalid 'missing-uncertainty'
    Assert-Throws { & $selector -CandidatePaths $invalidPath -ReportPath $badReport } 'MEASUREMENT_UNCERTAINTY_REQUIRED'

    $spanEnd.blocks[-1] | Add-Member -NotePropertyName continuationMm -NotePropertyValue 3
    $continuationPath = Write-Window $spanEnd 'single-span-block-continuation'
    $continuationPlan = & $solver -MeasurementPath $continuationPath
    Assert-Equal $continuationPlan.status 'ready-for-native-check'
    Assert-Equal $continuationPlan.placements[-1].occupiedMm 23
    Assert-Equal $continuationPlan.sourceIdentity $spanEnd.sourceIdentity
    Assert-Equal $continuationPlan.measurementSha256 (Get-FileHash -LiteralPath $continuationPath).Hash
    $continuationPlanPath = Write-Window $continuationPlan 'single-span-block-plan'
    $continuationReview = & $reviewer -MeasurementPath $continuationPath -PlanPath $continuationPlanPath | ConvertFrom-Json
    Assert-Equal $continuationReview.status 'robust-under-supplied-bounds'

    $spanEnd.blocks[-1].continuationMm = 4
    $changedPath = Write-Window $spanEnd 'same-source-changed-measurement'
    Assert-Throws { & $reviewer -MeasurementPath $changedPath -PlanPath $continuationPlanPath } 'LAYOUT_PLAN_MEASUREMENT_MISMATCH'
    $continuationPlan.sourceIdentity = 'synthetic-different-origin'
    Assert-Throws { & $reviewer -MeasurementPath $continuationPath -Plan $continuationPlan } 'LAYOUT_PLAN_MEASUREMENT_MISMATCH'

    $crossSpan = @{
        version = 1; sourceIdentity = 'synthetic-cross-span'; startIndex = 100; endIndex = 103
        blocks = @(
            @{ startIndex = 100; endIndex = 101; kind = 'body'; advanceMm = 2; canBreakAfter = $true; errorBelowMm = 0; errorAboveMm = 0 }
            @{ startIndex = 101; endIndex = 102; kind = 'span'; advanceMm = 2; canBreakAfter = $true; errorBelowMm = 0; errorAboveMm = 0 }
            @{ startIndex = 102; endIndex = 103; kind = 'body'; advanceMm = 2; errorBelowMm = 0; errorAboveMm = 0 }
        )
        slots = @(@{ page = 2; kind = 'column'; capacityMm = 6; maxBlankMm = 0 })
    }
    $crossSpanPath = Write-Window $crossSpan 'cross-span-final'
    Assert-Equal (& $solver -MeasurementPath $crossSpanPath).status 'no-candidate-in-window'
    $crossSpanReport = Join-Path $temp 'cross-span-report.json'
    Assert-Equal (& $selector -CandidatePaths $crossSpanPath -ReportPath $crossSpanReport) 'no-robust-offline-plan'
    $crossSpan.endIndex = 104
    $crossSpan.blocks += @{ startIndex = 103; endIndex = 104; kind = 'body'; advanceMm = 2; errorBelowMm = 0; errorAboveMm = 0 }
    $crossSpan.blocks[2].canBreakAfter = $true
    $crossSpan.slots[0].requiredEndIndex = 3
    $crossSpan.slots += @{ page = 2; kind = 'column'; capacityMm = 2; maxBlankMm = 0 }
    $crossSpanPath = Write-Window $crossSpan 'cross-span-pinned'
    Assert-Equal (& $solver -MeasurementPath $crossSpanPath).status 'no-candidate-in-window'

    $alternativeHeight = @{
        version = 1; sourceIdentity = 'synthetic-alternative-height'; startIndex = 200; endIndex = 201
        blocks = @(@{ startIndex = 200; endIndex = 201; kind = 'body'; advanceMm = 10; compressMm = 1; errorBelowMm = 0; errorAboveMm = 1 })
        slots = @(@{ page = 2; kind = 'column'; capacityMm = 10; maxBlankMm = 2 })
    }
    $alternativePath = Write-Window $alternativeHeight 'alternative-height'
    $alternativeReport = Join-Path $temp 'alternative-height-report.json'
    Assert-Equal (& $selector -CandidatePaths $alternativePath -ReportPath $alternativeReport) 'no-robust-offline-plan'
    $evaluated = (Get-Content -LiteralPath $alternativeReport -Raw | ConvertFrom-Json).candidates[0]
    Assert-Equal $evaluated.plan.placements[0].occupiedMm 10
    Assert-Equal $evaluated.review.issues[0].code 'MAY_OVERFLOW'
    $compressedPlan = & $solver -MeasurementPath $alternativePath
    $compressedPlan.placements[0].occupiedMm = 9
    $compressedPlan.placements[0].blankMm = 1
    $compressedPlan.placements[0].adjustmentMm = -1
    $compressedReview = & $reviewer -MeasurementPath $alternativePath -Plan $compressedPlan | ConvertFrom-Json
    Assert-Equal $compressedReview.status 'robust-under-supplied-bounds'

    'PASS offline page-window selection, span budgets, uncertainty, source range, coverage, and tail alignment'
} finally {
    Get-ChildItem -LiteralPath $temp -File | ForEach-Object { Remove-Item -LiteralPath $_.FullName }
    Remove-Item -LiteralPath $temp
}
