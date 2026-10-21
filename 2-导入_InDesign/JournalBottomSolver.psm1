$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-RequiredNumber {
    param([object]$Value, [string]$Name)
    if ($null -eq $Value) { throw "BOTTOM_INPUT_MISSING $Name" }
    $number = 0.0
    if (-not [double]::TryParse([string]$Value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        throw "BOTTOM_INPUT_NUMBER $Name"
    }
    if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) { throw "BOTTOM_INPUT_NUMBER $Name" }
    $number
}

function Get-OptionalField {
    param([object]$Object,[string]$Name)
    if($Object -is [Collections.IDictionary]){if($Object.Contains($Name)){return [pscustomobject]@{Found=$true;Value=$Object[$Name]}}}
    else{$property=$Object.PSObject.Properties[$Name];if($null -ne $property){return [pscustomobject]@{Found=$true;Value=$property.Value}}}
    [pscustomobject]@{Found=$false;Value=$null}
}
function Get-NormalizedColumn {
    param([object]$Column)
    if ([string]::IsNullOrWhiteSpace([string]$Column.id)) { throw 'BOTTOM_INPUT_MISSING columns.id' }
    $currentBottom = Get-RequiredNumber $Column.currentBottomPt "$($Column.id).currentBottomPt"
    $targetBottom = Get-RequiredNumber $Column.targetBottomPt "$($Column.id).targetBottomPt"
    $leading = [Collections.Generic.List[object]]::new()
    foreach ($item in @($Column.leadingGroups) | Sort-Object { [string]$_.id }) {
        $kind = [string]$item.kind
        if ($kind -notin @('body','reference')) { throw "BOTTOM_LEADING_KIND $($Column.id)/$($item.id)" }
        $current = Get-RequiredNumber $item.currentPt "$($item.id).currentPt"
        $minimum = Get-RequiredNumber $item.minPt "$($item.id).minPt"
        $maximum = Get-RequiredNumber $item.maxPt "$($item.id).maxPt"
        $lines = Get-RequiredNumber $item.lineCount "$($item.id).lineCount"
        if ($lines -le 0 -or $lines -ne [math]::Truncate($lines)) { throw "BOTTOM_LINE_COUNT $($item.id)" }
        $intervalProperty=Get-OptionalField $item 'baselineIntervals'
        $intervals=if(-not $intervalProperty.Found){[math]::Max(0,$lines-1)}else{Get-RequiredNumber $intervalProperty.Value "$($item.id).baselineIntervals"}
        if($intervals -lt 0 -or $intervals -gt $lines -or $intervals -ne [math]::Truncate($intervals)){throw "BOTTOM_BASELINE_INTERVALS $($item.id)"}
        if ($kind -eq 'body') { $minimum=[math]::Max($minimum,14.8); $maximum=[math]::Min($maximum,16.0) }
        else { $minimum=[math]::Max($minimum,12.6); $maximum=[math]::Min($maximum,13.4) }
        if ($minimum -gt $maximum -or $current -lt $minimum-0.000001 -or $current -gt $maximum+0.000001) {
            throw "BOTTOM_LEADING_RANGE $($Column.id)/$($item.id)"
        }
        $targetProperty=Get-OptionalField $item 'target'; $target=if($targetProperty.Found){$targetProperty.Value}else{$null}
        $leading.Add([pscustomobject]@{ Id=[string]$item.id; Kind='leading'; Role=$kind; Current=$current; Min=$minimum; Max=$maximum; Coefficient=$intervals; Target=$target })
    }
    $tracking = [Collections.Generic.List[object]]::new()
    foreach ($item in @($Column.trackingCandidates) | Sort-Object { [string]$_.id }) {
        $current = Get-RequiredNumber $item.current "$($item.id).current"
        $lineHeight = Get-RequiredNumber $item.lineHeightPt "$($item.id).lineHeightPt"
        if ([math]::Abs($current) -gt 20 -or $lineHeight -le 0) { throw "BOTTOM_TRACKING_RANGE $($Column.id)/$($item.id)" }
        $outcomes = [Collections.Generic.List[object]]::new(); $hasCurrent = $false
        foreach ($outcome in @($item.outcomes)) {
            $value = Get-RequiredNumber $outcome.tracking "$($item.id).outcomes.tracking"
            $lineDelta = Get-RequiredNumber $outcome.lineDelta "$($item.id).outcomes.lineDelta"
            if ([math]::Abs($value) -gt 20 -or $lineDelta -ne [math]::Truncate($lineDelta)) { continue }
            if ($outcome.orphanFree -ne $true) { continue }
            if ([math]::Abs($value-$current) -lt 0.000001 -and $lineDelta -eq 0) { $hasCurrent = $true }
            $outcomes.Add([pscustomobject]@{ Tracking=$value; LineDelta=[int]$lineDelta; Effect=$lineDelta*$lineHeight })
        }
        if (-not $hasCurrent) { throw "BOTTOM_TRACKING_CURRENT_MISSING $($Column.id)/$($item.id)" }
        $targetProperty=Get-OptionalField $item 'target'; $target=if($targetProperty.Found){$targetProperty.Value}else{$null}
        $tracking.Add([pscustomobject]@{ Id=[string]$item.id; Current=$current; Target=$target; Outcomes=@($outcomes | Sort-Object @{Expression={ [math]::Abs($_.Tracking-$current) }},Tracking,LineDelta) })
    }
    $figures = [Collections.Generic.List[object]]::new()
    foreach ($item in @($Column.figures) | Sort-Object { [string]$_.id }) {
        $height = Get-RequiredNumber $item.currentHeightPt "$($item.id).currentHeightPt"
        $current = Get-RequiredNumber $item.currentScalePct "$($item.id).currentScalePct"
        $minimum = [math]::Max((Get-RequiredNumber $item.minScalePct "$($item.id).minScalePct"),$current-5)
        $maximum = [math]::Min((Get-RequiredNumber $item.maxScalePct "$($item.id).maxScalePct"),$current+5)
        if ($height -le 0 -or $current -le 0 -or $minimum -gt $current -or $maximum -lt $current) { throw "BOTTOM_FIGURE_RANGE $($Column.id)/$($item.id)" }
        $targetProperty=Get-OptionalField $item 'target'; $target=if($targetProperty.Found){$targetProperty.Value}else{$null}
        $figures.Add([pscustomobject]@{ Id=[string]$item.id; Kind='figure'; Role='figure'; Current=$current; Min=$minimum; Max=$maximum; Coefficient=$height/$current; Target=$target })
    }
    $tables = [Collections.Generic.List[object]]::new()
    foreach ($item in @($Column.tableRows) | Sort-Object { [string]$_.id }) {
        if ($item.singleLine -ne $true) { continue }
        $current = Get-RequiredNumber $item.currentHeightMm "$($item.id).currentHeightMm"
        $minimum = [math]::Max((Get-RequiredNumber $item.minHeightMm "$($item.id).minHeightMm"),4.8)
        $maximum = [math]::Min((Get-RequiredNumber $item.maxHeightMm "$($item.id).maxHeightMm"),5.5)
        $countProperty=Get-OptionalField $item 'count'
        $count = if (-not $countProperty.Found) { 1.0 } else { Get-RequiredNumber $countProperty.Value "$($item.id).count" }
        if ($count -le 0 -or $minimum -gt $current -or $maximum -lt $current) { throw "BOTTOM_TABLE_RANGE $($Column.id)/$($item.id)" }
        $targetProperty=Get-OptionalField $item 'target'; $target=if($targetProperty.Found){$targetProperty.Value}else{$null}
        $tables.Add([pscustomobject]@{ Id=[string]$item.id; Kind='table'; Role='single-line'; Current=$current; Min=$minimum; Max=$maximum; Coefficient=$count*72/25.4; Target=$target })
    }
    [pscustomobject]@{ Id=[string]$Column.id; Delta=$targetBottom-$currentBottom; CurrentBottom=$currentBottom; TargetBottom=$targetBottom; Leading=@($leading); Tracking=@($tracking); Figures=@($figures); Tables=@($tables) }
}

function Get-TrackingStates {
    param([object[]]$Candidates, [bool]$IncludeAlternatives)
    $states = @([pscustomobject]@{ Effect=0.0; Score=0.0; Actions=@() })
    foreach ($candidate in $Candidates) {
        $options = if ($IncludeAlternatives) { @($candidate.Outcomes) } else { @($candidate.Outcomes | Where-Object { [math]::Abs($_.Tracking-$candidate.Current)-lt 0.000001 -and $_.LineDelta-eq 0 }) }
        $next = [Collections.Generic.List[object]]::new()
        foreach ($state in $states) {
            foreach ($option in $options) {
                $actions = @($state.Actions)
                if ([math]::Abs($option.Tracking-$candidate.Current)-gt 0.000001 -or $option.LineDelta-ne 0) {
                    $actions += [pscustomobject][ordered]@{ kind='tracking'; id=$candidate.Id; from=[math]::Round($candidate.Current,6); to=[math]::Round($option.Tracking,6); lineDelta=$option.LineDelta; effectPt=[math]::Round($option.Effect,6); orphanFree=$true; target=$candidate.Target }
                }
                $next.Add([pscustomobject]@{ Effect=$state.Effect+$option.Effect; Score=$state.Score+[math]::Abs($option.Tracking-$candidate.Current); Actions=$actions })
                if ($next.Count -gt 512) { throw 'BOTTOM_TRACKING_COMBINATIONS_EXCEEDED 512' }
            }
        }
        $states = @($next)
    }
    @($states | Sort-Object Score,Effect)
}

function Add-ContinuousTier {
    param([object]$State, [object[]]$Knobs)
    if ([math]::Abs($State.Residual) -lt 0.0000001 -or $Knobs.Count -eq 0) { return $State }
    $direction = [math]::Sign($State.Residual); $capacities = @(); $total = 0.0
    foreach ($knob in $Knobs) {
        $limit = if ($direction -gt 0) { $knob.Max } else { $knob.Min }
        $capacity = [math]::Abs(($limit-$knob.Current)*$knob.Coefficient)
        $capacities += [pscustomobject]@{ Knob=$knob; Limit=$limit; Effect=$capacity }
        $total += $capacity
    }
    if ($total -lt 0.0000001) { return $State }
    $factor = [math]::Min(1.0,[math]::Abs($State.Residual)/$total); $applied = 0.0
    foreach ($entry in $capacities) {
        if ($entry.Effect -lt 0.0000001) { continue }
        $knob=$entry.Knob; $target=$knob.Current+($entry.Limit-$knob.Current)*$factor
        $effect=($target-$knob.Current)*$knob.Coefficient; $applied += $effect
        switch ($knob.Kind) {
            'leading' { $State.Actions.Add([pscustomobject][ordered]@{ kind='leading'; id=$knob.Id; role=$knob.Role; fromPt=[math]::Round($knob.Current,6); toPt=[math]::Round($target,6); effectPt=[math]::Round($effect,6); target=$knob.Target }) }
            'figure' { $State.Actions.Add([pscustomobject][ordered]@{ kind='figure-height'; id=$knob.Id; fromScalePct=[math]::Round($knob.Current,6); toScalePct=[math]::Round($target,6); effectPt=[math]::Round($effect,6); target=$knob.Target }) }
            'table' { $State.Actions.Add([pscustomobject][ordered]@{ kind='table-row-height'; id=$knob.Id; fromMm=[math]::Round($knob.Current,6); toMm=[math]::Round($target,6); effectPt=[math]::Round($effect,6); target=$knob.Target }) }
        }
    }
    $State.Residual -= $applied
    $State
}

function Get-ColumnPlan {
    param([object]$Column, [double]$Tolerance)
    $stages = @(
        [pscustomobject]@{ Name='leading'; Tracking=$false; Figure=$false; Table=$false },
        [pscustomobject]@{ Name='tracking'; Tracking=$true; Figure=$false; Table=$false },
        [pscustomobject]@{ Name='figure'; Tracking=$true; Figure=$true; Table=$false },
        [pscustomobject]@{ Name='table'; Tracking=$true; Figure=$true; Table=$true }
    )
    $bestResidual = [double]::PositiveInfinity
    foreach ($stage in $stages) {
        $solutions = [Collections.Generic.List[object]]::new()
        foreach ($trackingState in @(Get-TrackingStates $Column.Tracking $stage.Tracking)) {
            $actions = [Collections.Generic.List[object]]::new(); foreach ($action in $trackingState.Actions) { $actions.Add($action) }
            $state=[pscustomobject]@{ Residual=$Column.Delta-$trackingState.Effect; Actions=$actions }
            $state=Add-ContinuousTier $state $Column.Leading
            if ($stage.Figure) { $state=Add-ContinuousTier $state $Column.Figures }
            if ($stage.Table) { $state=Add-ContinuousTier $state $Column.Tables }
            if ([math]::Abs($state.Residual) -lt [math]::Abs($bestResidual)) { $bestResidual=$state.Residual }
            if ([math]::Abs($state.Residual) -le $Tolerance) { $solutions.Add([pscustomobject]@{ TrackingScore=$trackingState.Score; State=$state }) }
        }
        if ($solutions.Count) {
            $chosen=$solutions | Sort-Object TrackingScore,@{Expression={$_.State.Actions.Count}} | Select-Object -First 1
            return [pscustomobject][ordered]@{ id=$Column.Id; status='ready'; stage=$stage.Name; requiredDeltaPt=[math]::Round($Column.Delta,6); achievedDeltaPt=[math]::Round($Column.Delta-$chosen.State.Residual,6); residualPt=[math]::Round($chosen.State.Residual,6); adjustments=@($chosen.State.Actions) }
        }
    }
    [pscustomobject][ordered]@{ id=$Column.Id; status='blocked'; code='BOTTOM_UNSOLVABLE'; requiredDeltaPt=[math]::Round($Column.Delta,6); bestResidualPt=[math]::Round($bestResidual,6); adjustments=@() }
}

function New-JournalBottomPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$InputObject)
    if ([int]$InputObject.version -ne 1) { throw 'BOTTOM_INPUT_VERSION expected=1' }
    $toleranceProperty=Get-OptionalField $InputObject 'tolerancePt'
    $tolerance = if (-not $toleranceProperty.Found) { 0.25 } else { Get-RequiredNumber $toleranceProperty.Value 'tolerancePt' }
    if ($tolerance -le 0 -or $tolerance -gt 1) { throw 'BOTTOM_TOLERANCE_RANGE (0,1]' }
    $columns=@($InputObject.columns); if (-not $columns.Count) { throw 'BOTTOM_INPUT_MISSING columns' }
    $plans=[Collections.Generic.List[object]]::new(); $ids=@{}
    foreach ($sourceColumn in $columns) {
        $column=Get-NormalizedColumn $sourceColumn
        if ($ids.ContainsKey($column.Id)) { throw "BOTTOM_COLUMN_DUPLICATE $($column.Id)" }; $ids[$column.Id]=$true
        $plans.Add((Get-ColumnPlan $column $tolerance))
    }
    $blocked=@($plans | Where-Object status -eq 'blocked')
    [pscustomobject][ordered]@{ schemaVersion=1; engine='journal-bottom-solver'; status=if($blocked.Count){'blocked'}else{'ready'}; tolerancePt=$tolerance; adobeCalls=0; blankSpaceAllowed=$false; columns=@($plans); blockedColumns=@($blocked | ForEach-Object { $_.id }) }
}

Export-ModuleMember -Function New-JournalBottomPlan
