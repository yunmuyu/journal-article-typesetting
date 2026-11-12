#Requires -Version 7.0
param(
    [Parameter(Mandatory)][string]$MeasurementPath,
    [Parameter(Mandatory, ParameterSetName='File')][string]$PlanPath,
    [Parameter(Mandatory, ParameterSetName='Object')][psobject]$Plan
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Read-PageWindowInput.ps1')
$measurementSha256 = (Get-FileHash -LiteralPath $MeasurementPath).Hash
$inputData = Read-PageWindowInput $MeasurementPath -RequireUncertainty
if ($PlanPath) { $plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json -Depth 100 }
if ($plan.status -ne 'ready-for-native-check' -or $plan.placements.Count -ne $inputData.slots.Count -or
    $plan.startIndex -ne $inputData.startIndex -or $plan.endIndex -ne $inputData.endIndex) {
    throw 'COMPLETE_OFFLINE_PLAN_REQUIRED'
}
if ($plan.sourceIdentity -isnot [string] -or
    ![string]::Equals($plan.sourceIdentity, $inputData.sourceIdentity, [StringComparison]::Ordinal) -or
    $plan.measurementSha256 -isnot [string] -or $plan.measurementSha256 -ne $measurementSha256) {
    throw 'LAYOUT_PLAN_MEASUREMENT_MISMATCH'
}
$blocks = $inputData.blocks
$byStart = @{}
for ($i = 0; $i -lt $blocks.Count; $i++) {
    $block = $blocks[$i]
    $byStart[[long]$block.startIndex] = $i
}
$issues = [Collections.Generic.List[object]]::new()
$records = [Collections.Generic.List[object]]::new()
$expectedStart = $inputData.startIndex
$left = $null
$upperBand = $null
$spanThrough = $null
$spanPage = $null
for ($i = 0; $i -lt $plan.placements.Count; $i++) {
    $placement = $plan.placements[$i]
    $slot = $inputData.slots[$i]
    if ($placement.startIndex -ne $expectedStart -or !$slot.page.Equals($placement.page) -or
        $placement.kind -cne $slot.kind -or !(Test-WindowIndex $placement.startIndex) -or !(Test-WindowIndex $placement.endIndex) -or
        !(Test-WindowNumber $placement.occupiedMm) -or $placement.endIndex -le $placement.startIndex -or
        !$byStart.ContainsKey([long]$expectedStart)) {
        throw "LAYOUT_SLOT_IDENTITY $i"
    }
    $low = [double]$placement.occupiedMm
    $high = $low
    $offset = $byStart[[long]$expectedStart]
    $blockStart = $offset
    $nominal = [double]$blocks[$blockStart].continuationMm
    $compress = 0.0
    $expand = 0.0
    if ($null -ne $slot.requiredStartIndex -and $blockStart -ne $slot.requiredStartIndex) {
        throw "LAYOUT_SLOT_ENDPOINT $i"
    }
    do {
        if ($offset -ge $blocks.Count) { throw "LAYOUT_SLOT_ENDPOINT $i" }
        $block = $blocks[$offset++]
        if (($slot.kind -eq 'span') -ne ($block.kind -eq 'span')) { throw "LAYOUT_BLOCK_KIND $i" }
        $nominal += $block.advanceMm
        $compress += [double]$block.compressMm
        $expand += [double]$block.expandMm
        $low -= $block.errorBelowMm
        $high += $block.errorAboveMm
    } while ($block.endIndex -lt $placement.endIndex)
    if ($block.endIndex -ne $placement.endIndex -or
        ($null -ne $slot.requiredEndIndex -and $offset -ne $slot.requiredEndIndex) -or
        ($slot.kind -eq 'span' -and $offset -ne $blockStart + 1) -or
        ($offset -lt $blocks.Count -and !$block.canBreakAfter -and $null -eq $slot.observedOccupiedMm)) {
        throw "LAYOUT_SLOT_ENDPOINT $i"
    }
    if ($null -ne $slot.observedOccupiedMm -and [math]::Abs($placement.occupiedMm - $slot.observedOccupiedMm) -gt 0.0001) {
        $issues.Add([ordered]@{ code = 'OBSERVATION_MISMATCH'; slot = $i; page = $slot.page })
    } elseif ($null -eq $slot.observedOccupiedMm -and
        ($placement.occupiedMm -lt $nominal - $compress - 0.0001 -or
            $placement.occupiedMm -gt $nominal + $expand + 0.0001)) {
        $issues.Add([ordered]@{ code = 'ADJUSTMENT_OUT_OF_RANGE'; slot = $i; page = $slot.page })
    }
    $expectedStart = $block.endIndex

    $capacityLow = [double]$slot.capacityMm
    $capacityHigh = $capacityLow
    if ($slot.kind -eq 'span') {
        if (!$upperBand -or $upperBand.page -ne $slot.page) { throw "LAYOUT_SPAN_WITHOUT_UPPER_BAND $i" }
        $capacityLow -= $upperBand.high
        $capacityHigh -= $upperBand.low
        $spanThrough = @{ low = $upperBand.low + $low; high = $upperBand.high + $high }
        $spanPage = $slot.page
        $upperBand = $null
    } elseif ($slot.belowSpan -eq $true) {
        if (!$spanThrough -or $spanPage -ne $slot.page) { throw "LAYOUT_LOWER_WITHOUT_SPAN $i" }
        $capacityLow -= $spanThrough.high
        $capacityHigh -= $spanThrough.low
    }
    if ($high -gt $capacityLow + 0.0001) {
        $issues.Add([ordered]@{ code = 'MAY_OVERFLOW'; slot = $i; page = $slot.page
            excessMm = [math]::Round($high - $capacityLow, 4) })
    }
    if (($slot.kind -eq 'column' -or $slot.closePage -eq $true) -and
        $capacityHigh - $low -gt [double]$slot.maxBlankMm + 0.0001) {
        $issues.Add([ordered]@{ code = 'MAY_LEAVE_GAP'; slot = $i; page = $slot.page
            blankMm = [math]::Round($capacityHigh - $low, 4) })
    }
    if ($slot.kind -in 'span-left','tail-left') {
        $left = @{ low = $low; high = $high; page = $slot.page; kind = $slot.kind }
    }
    if ($slot.kind -in 'span-right','tail-right') {
        if (!$left -or $left.page -ne $slot.page -or $left.kind -ne ($slot.kind -replace '-right$', '-left')) {
            throw "LAYOUT_PAIR_IDENTITY $i"
        }
        $allowedRightShort = if ($slot.kind -eq 'tail-right') { 0.1 } else { [double]$slot.maxBlankMm }
        $allowedLeftShort = if ($slot.kind -eq 'tail-right') { 0.1 } else { 0 }
        $pairTolerance = if ($slot.kind -eq 'tail-right') { 0.0000001 } else { 0.0001 }
        if ($left.high - $low -gt $allowedRightShort + $pairTolerance -or
            $high - $left.low -gt $allowedLeftShort + $pairTolerance) {
            $issues.Add([ordered]@{ code = 'MAY_MISS_BOTTOM_ALIGNMENT'; slot = $i; page = $slot.page
                maximumRightShortMm = [math]::Round($left.high - $low, 4)
                maximumLeftShortMm = [math]::Round($high - $left.low, 4) })
        }
        if ($slot.kind -eq 'span-right') {
            $upperBand = @{ page = $slot.page; low = [math]::Max($left.low, $low); high = [math]::Max($left.high, $high) }
        }
        $left = $null
    }
    $records.Add([ordered]@{ page = $slot.page; kind = $slot.kind; startIndex = $placement.startIndex
        endIndex = $placement.endIndex; minimumOccupiedMm = $low; maximumOccupiedMm = $high
        minimumCapacityMm = $capacityLow; maximumCapacityMm = $capacityHigh })
}
if ($expectedStart -ne $inputData.endIndex -or $left -or $upperBand) { throw 'LAYOUT_COVERAGE_INCOMPLETE' }
if ((Get-FileHash -LiteralPath $MeasurementPath).Hash -ne $measurementSha256) { throw 'LAYOUT_INPUT_CHANGED' }
[ordered]@{
    status = if ($issues.Count) { 'measurement-risk' } else { 'robust-under-supplied-bounds' }
    adobeCalls = 0; issues = @($issues); slots = @($records)
} | ConvertTo-Json -Depth 15
