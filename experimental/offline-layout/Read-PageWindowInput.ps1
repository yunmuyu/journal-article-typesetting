function Test-WindowIndex($Value) {
    return ($Value -is [int] -or $Value -is [long]) -and $Value -ge 0
}

function Test-WindowNumber($Value, [switch]$Positive) {
    return ($Value -is [int] -or $Value -is [long] -or $Value -is [double]) -and
        [double]::IsFinite($Value) -and $Value -ge 0 -and (!$Positive -or $Value -gt 0)
}

function Read-PageWindowInput([string]$Path, [switch]$RequireUncertainty) {
    $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100
    if (!(Test-WindowIndex $data.version) -or $data.version -ne 1 -or
        $data.blocks -isnot [array] -or !$data.blocks.Count -or
        $data.slots -isnot [array] -or !$data.slots.Count) {
        throw 'PAGE_WINDOW_INPUT_INVALID'
    }
    if ($data.sourceIdentity -isnot [string] -or [string]::IsNullOrWhiteSpace($data.sourceIdentity)) {
        throw "LAYOUT_SOURCE_IDENTITY_REQUIRED $Path"
    }
    if (!(Test-WindowIndex $data.startIndex) -or !(Test-WindowIndex $data.endIndex) -or
        $data.startIndex -ne $data.blocks[0].startIndex -or $data.endIndex -ne $data.blocks[-1].endIndex) {
        throw 'PAGE_WINDOW_ENDPOINT_MISMATCH'
    }

    $expectedStart = $data.startIndex
    for ($i = 0; $i -lt $data.blocks.Count; $i++) {
        $block = $data.blocks[$i]
        if (!(Test-WindowIndex $block.startIndex) -or !(Test-WindowIndex $block.endIndex) -or
            $block.startIndex -ne $expectedStart -or $block.endIndex -le $block.startIndex -or
            !(Test-WindowNumber $block.advanceMm -Positive) -or
            $block.kind -isnot [string] -or [string]::IsNullOrWhiteSpace($block.kind) -or
            ($null -ne $block.canBreakAfter -and $block.canBreakAfter -isnot [bool])) {
            throw "PAGE_WINDOW_BLOCK_INVALID $i"
        }
        foreach ($field in 'compressMm','expandMm','continuationMm','errorBelowMm','errorAboveMm') {
            $value = $block.$field
            if ($null -ne $value -and !(Test-WindowNumber $value)) {
                throw "PAGE_WINDOW_BLOCK_INVALID $i $field"
            }
        }
        if ($block.compressMm -ge $block.advanceMm) { throw "PAGE_WINDOW_BLOCK_INVALID $i compressMm" }
        if ($RequireUncertainty -and ($null -eq $block.errorBelowMm -or $null -eq $block.errorAboveMm)) {
            throw "MEASUREMENT_UNCERTAINTY_REQUIRED $($block.startIndex)"
        }
        $expectedStart = $block.endIndex
    }

    $previous = $null
    for ($i = 0; $i -lt $data.slots.Count; $i++) {
        $slot = $data.slots[$i]
        if ($slot.kind -cnotin 'column','span-left','span-right','span','tail-left','tail-right' -or
            (!(Test-WindowIndex $slot.page) -and
                ($slot.page -isnot [string] -or [string]::IsNullOrWhiteSpace($slot.page))) -or
            !(Test-WindowNumber $slot.capacityMm -Positive) -or !(Test-WindowNumber $slot.maxBlankMm) -or
            ($null -ne $slot.closePage -and $slot.closePage -isnot [bool]) -or
            ($null -ne $slot.belowSpan -and $slot.belowSpan -isnot [bool])) {
            throw "PAGE_WINDOW_SLOT_INVALID $i"
        }
        foreach ($field in 'requiredStartIndex','requiredEndIndex') {
            $value = $slot.$field
            if ($null -ne $value -and (!(Test-WindowIndex $value) -or $value -gt $data.blocks.Count)) {
                throw "PAGE_WINDOW_SLOT_INVALID $i $field"
            }
        }
        if ($slot.requiredStartIndex -ge $data.blocks.Count -or
            ($null -ne $slot.requiredEndIndex -and ($slot.requiredEndIndex -eq 0 -or
                ($null -ne $slot.requiredStartIndex -and $slot.requiredStartIndex -ge $slot.requiredEndIndex) -or
                ($i -eq $data.slots.Count - 1 -and $slot.requiredEndIndex -ne $data.blocks.Count)))) {
            throw "PAGE_WINDOW_SLOT_INVALID $i block offsets"
        }
        if ($null -ne $slot.observedOccupiedMm -and (!(Test-WindowNumber $slot.observedOccupiedMm -Positive) -or
            $null -eq $slot.requiredStartIndex -or ($null -eq $slot.requiredEndIndex -and $i -ne $data.slots.Count - 1))) {
            throw "PAGE_WINDOW_SLOT_INVALID $i observedOccupiedMm"
        }

        if ($previous.kind -in 'span-left','span-right','tail-left') {
            $nextKind = switch ($previous.kind) {
                'span-left' { 'span-right' }
                'span-right' { 'span' }
                'tail-left' { 'tail-right' }
            }
            if ($slot.kind -ne $nextKind -or $slot.page -cne $previous.page -or
                ($slot.kind -eq 'tail-right' -and [bool]$slot.belowSpan -ne [bool]$previous.belowSpan)) {
                throw "PAGE_WINDOW_SPAN_PAIR_INVALID $i"
            }
        } elseif ($slot.kind -in 'span-right','span','tail-right') {
            throw "PAGE_WINDOW_SPAN_PAIR_INVALID $i"
        }
        if ($slot.belowSpan -and ($slot.kind -notin 'column','tail-left','tail-right' -or
            $slot.page -cne $previous.page -or ($previous.kind -ne 'span' -and !$previous.belowSpan))) {
            throw "PAGE_WINDOW_LOWER_BAND_WITHOUT_SPAN $i"
        }
        $previous = $slot
    }
    if ($previous.kind -in 'span-left','span-right','tail-left') { throw 'PAGE_WINDOW_SPAN_PAIR_INVALID' }
    return $data
}
