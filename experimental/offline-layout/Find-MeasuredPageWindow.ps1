#Requires -Version 7.0
param([Parameter(Mandatory)][string]$MeasurementPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Read-PageWindowInput.ps1')
$measurementSha256 = (Get-FileHash -LiteralPath $MeasurementPath).Hash
$inputData = Read-PageWindowInput $MeasurementPath
$blocks = $inputData.blocks
$slots = $inputData.slots
$prefix=[double[]]::new($blocks.Count+1)
$compression=[double[]]::new($blocks.Count+1)
$expansion=[double[]]::new($blocks.Count+1)
for($i=0;$i -lt $blocks.Count;$i++){
    $block=$blocks[$i]
    $prefix[$i+1]=$prefix[$i]+$block.advanceMm
    $compression[$i+1]=$compression[$i]+[double]$block.compressMm
    $expansion[$i+1]=$expansion[$i]+[double]$block.expandMm
}

# The state carries the source boundary and heights used by later slots.
$states=@{ '0'=@{index=0;totalGap=0.0;change=0.0;leftHeight=$null;upperHeight=$null;usedAbove=$null;placements=@()} }
$rejections=[ordered]@{capacity=0;largeGap=0;spanBalance=0}
$reachedSlots=0
$slotEvidence=@()
$tolerance=.01
for($slotIndex=0;$slotIndex -lt $slots.Count;$slotIndex++){
    $slot=$slots[$slotIndex]
    $requiredEnd=if($null -ne $slot.requiredEndIndex){$slot.requiredEndIndex}elseif($slotIndex -eq $slots.Count-1){$blocks.Count}
    $next=@{}
    $closestGap=$null
    $closestOverflow=$null
    foreach($stateKey in ($states.Keys | Sort-Object)){
        $state=$states[$stateKey]
        if($null -ne $slot.requiredStartIndex -and $state.index -ne $slot.requiredStartIndex){continue}
        if(($slot.kind -in @('span-right','tail-right')) -ne ($null -ne $state.leftHeight)){
            throw 'PAGE_WINDOW_SPAN_PAIR_INVALID'
        }
        $capacity=[double]$slot.capacityMm
        if($slot.kind -eq 'span'){$capacity-=[double]$state.upperHeight}
        if($slot.belowSpan -eq $true){
            if($null -eq $state.usedAbove){throw 'PAGE_WINDOW_LOWER_BAND_WITHOUT_SPAN'}
            $capacity-=$state.usedAbove
        }
        for($end=$state.index+1;$end -le $blocks.Count;$end++){
            if($null -ne $requiredEnd -and $end -gt $requiredEnd){break}
            $isSpan=$blocks[$state.index].kind -eq 'span'
            if(($slot.kind -eq 'span') -ne $isSpan -or ($isSpan -and $end -gt $state.index+1)){break}
            if(!$isSpan -and $blocks[$end-1].kind -eq 'span'){break}
            if($null -ne $requiredEnd -and $end -lt $requiredEnd){continue}
            $natural=$prefix[$end]-$prefix[$state.index]+[double]$blocks[$state.index].continuationMm
            $low=$natural-($compression[$end]-$compression[$state.index])
            $high=$natural+($expansion[$end]-$expansion[$state.index])
            if($null -ne $slot.observedOccupiedMm){
                $natural=[double]$slot.observedOccupiedMm
                $low=$natural
                $high=$natural
            }
            if($low -gt $capacity+$tolerance){
                $rejections.capacity++
                $overflow=$low-$capacity
                if($null -eq $closestOverflow -or $overflow -lt $closestOverflow){$closestOverflow=$overflow}
                break
            }
            if($end -lt $blocks.Count -and $blocks[$end-1].canBreakAfter -ne $true -and
                $null -eq $slot.observedOccupiedMm){continue}
            $isPairedColumn=$slot.kind -in @('span-left','span-right','tail-left','tail-right')
            if($isPairedColumn -and $slot.closePage -eq $true){
                $minimumHeight=$capacity-$slot.maxBlankMm
                if($high -lt $minimumHeight-.0000001){
                    $rejections.largeGap++
                    $shortfall=$capacity-$high
                    if($null -eq $closestGap -or $shortfall -lt $closestGap){$closestGap=$shortfall}
                    continue
                }
                $low=[math]::Max($low,$minimumHeight)
            }
            $height=[math]::Max($low,[math]::Min($natural,$capacity))
            if($slot.kind -eq 'column'){
                $height=[math]::Max($height,[math]::Min($high,$capacity-$slot.maxBlankMm))
            }
            $gap=if($slot.kind -eq 'column' -or $slot.closePage -eq $true){
                [math]::Max(0.0,$capacity-$height)
            }else{0.0}
            if($gap -gt $slot.maxBlankMm+$tolerance){
                $rejections.largeGap++
                if($null -eq $closestGap -or $gap -lt $closestGap){$closestGap=$gap}
                continue
            }
            $history=@($state.placements)
            $pairedGap=0.0
            $pairedChange=0.0
            if($slot.kind -in @('span-right','tail-right')){
                $left=$state.leftHeight
                $allowedDifference=if($slot.kind -eq 'span-right'){[double]$slot.maxBlankMm}else{.1}
                $rightMayBeLower=if($slot.kind -eq 'tail-right'){.1}else{0.0}
                $rightLow=[math]::Max($low,$left.min-$allowedDifference)
                $rightHigh=[math]::Min([math]::Min($high,$capacity),$left.max+$rightMayBeLower)
                $pairTolerance=if($slot.kind -eq 'tail-right'){.0000001}else{$tolerance}
                if($rightLow -gt $rightHigh+$pairTolerance){$rejections.spanBalance++;continue}
                $height=[math]::Max($rightLow,[math]::Min($rightHigh,$height))
                $leftHeightMm=[math]::Max([math]::Max($left.min,$height-$rightMayBeLower),
                    [math]::Min([math]::Min($left.max,$height+$allowedDifference),$left.natural))
                $pairedGap=[math]::Abs($leftHeightMm-$height)
                $previous=$history[-1].PSObject.Copy()
                $previous.occupiedMm=$leftHeightMm
                if($left.closePage){
                    $previous.blankMm=[math]::Max(0.0,$left.capacity-$leftHeightMm)
                    $pairedGap+=$previous.blankMm-$history[-1].blankMm
                }
                if($slot.closePage -eq $true){$gap=[math]::Max(0.0,$capacity-$height)}
                $previous.adjustmentMm=$leftHeightMm-$left.natural
                $pairedChange=[math]::Abs($previous.adjustmentMm)-[math]::Abs($history[-1].adjustmentMm)
                $history[-1]=$previous
            }
            $leftHeight=if($slot.kind -in @('span-left','tail-left')){
                @{min=$low;max=[math]::Min($high,$capacity);natural=$natural;closePage=$slot.closePage;capacity=$capacity}
            }else{$null}
            $upperHeight=if($slot.kind -eq 'span-right'){$leftHeightMm}else{$null}
            $usedAbove=if($slot.kind -eq 'span'){
                [double]$state.upperHeight+$height
            }elseif($slot.belowSpan -eq $true -and $slotIndex+1 -lt $slots.Count -and
                $slots[$slotIndex+1].belowSpan -eq $true){$state.usedAbove}
            $key="$end/$upperHeight/$usedAbove"
            if($leftHeight){$key+="/$($state.index)"}
            $totalGap=$gap+$state.totalGap+$pairedGap
            $change=$state.change+[math]::Abs($height-$natural)+$pairedChange
            $existing=$next[$key]
            if($existing -and ($existing.totalGap -lt $totalGap -or
                ($existing.totalGap -eq $totalGap -and $existing.change -le $change))){continue}
            $placement=[pscustomobject]@{page=$slot.page;kind=$slot.kind;startIndex=$blocks[$state.index].startIndex
                endIndex=$blocks[$end-1].endIndex;occupiedMm=$height;blankMm=$gap;adjustmentMm=$height-$natural}
            $next[$key]=@{index=$end;totalGap=$totalGap;change=$change;leftHeight=$leftHeight;upperHeight=$upperHeight;usedAbove=$usedAbove
                placements=$history+@($placement)}
        }
    }
    $slotEvidence+=@([pscustomobject]@{page=$slot.page;kind=$slot.kind;incoming=$states.Count
        outgoing=$next.Count;closestRejectedGapMm=$closestGap;closestOverflowMm=$closestOverflow})
    $states=$next
    if(!$states.Count){break}
    $reachedSlots++
}
$winner = if ($reachedSlots -eq $slots.Count) {
    $states.Keys | Sort-Object |
        ForEach-Object { $states[$_] } | Where-Object index -eq $blocks.Count |
        Sort-Object -Stable { $_.totalGap }, { $_.change } | Select-Object -First 1
}
if((Get-FileHash -LiteralPath $MeasurementPath).Hash -ne $measurementSha256){throw 'LAYOUT_INPUT_CHANGED'}
[pscustomobject]@{
    status=if($winner){'ready-for-native-check'}else{'no-candidate-in-window'}
    adobeCalls=0;sourceIdentity=$inputData.sourceIdentity;measurementSha256=$measurementSha256
    startIndex=$inputData.startIndex;endIndex=$inputData.endIndex
    placements=@($winner.placements | Where-Object { $null -ne $_ })
    reachedSlots=$reachedSlots;slotCount=$slots.Count
    blockedAt=if($reachedSlots -lt $slots.Count){$slots[$reachedSlots]}
    rejected=$rejections;slotEvidence=$slotEvidence
}
