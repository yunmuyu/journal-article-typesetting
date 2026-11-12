$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $root '2-导入_InDesign/JournalBottomSolver.psm1'
$entryPath = Join-Path $root '2-导入_InDesign/New-JournalBottomPlan.ps1'
function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function New-Column([double]$DeltaPt) {
    [ordered]@{ id='p2-left'; currentBottomPt=700.0; targetBottomPt=700.0+$DeltaPt; leadingGroups=@(); trackingCandidates=@(); figures=@(); tableRows=@() }
}
Import-Module $modulePath -Force

# Given a full column whose body lines can absorb the complete difference.
$column = New-Column 6
$column.leadingGroups = @([ordered]@{ id='body-main'; kind='body'; lineCount=20; currentPt=15; minPt=14.8; maxPt=16; target=[ordered]@{storyRole='body';startIndex=10;endIndex=30} })
# When the solver plans the adjustment.
$plan = New-JournalBottomPlan -InputObject ([ordered]@{ version=1; tolerancePt=0.01; columns=@($column) })
# Then it stops at a legal leading value.
Assert-True ($plan.status -eq 'ready' -and $plan.columns[0].stage -eq 'leading') 'leading-only plan should be ready'
Assert-True ([math]::Abs($plan.columns[0].adjustments[0].toPt-15.315789) -lt 0.000001) 'body leading should use 19 baseline intervals'
Assert-True ($plan.columns[0].adjustments[0].target.startIndex -eq 10) 'selected adjustment should preserve its InDesign target'

# Given a discrete local-tracking outcome that adds one orphan-free line.
$column = New-Column 13.2
$column.leadingGroups = @([ordered]@{ id='body-main'; kind='body'; lineCount=10; currentPt=15; minPt=14.8; maxPt=15.2 })
$column.trackingCandidates = @([ordered]@{
    id='paragraph-17'; current=0; lineHeightPt=15
    outcomes=@(
        [ordered]@{ tracking=0; lineDelta=0; orphanFree=$true },
        [ordered]@{ tracking=13.18; lineDelta=1; orphanFree=$true },
        [ordered]@{ tracking=8; lineDelta=1; orphanFree=$false }
    )
})
# When leading alone cannot solve the target.
$plan = New-JournalBottomPlan -InputObject ([ordered]@{ version=1; tolerancePt=0.01; columns=@($column) })
# Then it selects the valid tracking outcome within absolute 20.
$action = @($plan.columns[0].adjustments | Where-Object kind -eq 'tracking')[0]
Assert-True ($plan.status -eq 'ready' -and $plan.columns[0].stage -eq 'tracking') 'tracking-assisted plan should be ready'
Assert-True ([math]::Abs($action.to-13.18) -lt 0.000001 -and [math]::Abs($action.to) -le 20) 'valid orphan-free tracking should be selected'

# Twelve binary choices produce 4096 combinations but only thirteen distinct height effects.
$column = New-Column 90
$column.trackingCandidates = @(foreach ($i in 1..12) {
    [ordered]@{
        id="candidate-$i"; current=0; lineHeightPt=15
        outcomes=@(
            [ordered]@{ tracking=0; lineDelta=0; orphanFree=$true },
            [ordered]@{ tracking=(13-$i); lineDelta=1; orphanFree=$true }
        )
    }
})
$plan = New-JournalBottomPlan -InputObject ([ordered]@{ version=1; tolerancePt=0.01; columns=@($column) })
$actions = $plan.columns[0].adjustments
Assert-True ($plan.status -eq 'ready' -and $actions.Count -eq 6) 'equivalent tracking combinations must not exhaust the search limit'
Assert-True ((($actions.id | Sort-Object) -join ',') -eq 'candidate-10,candidate-11,candidate-12,candidate-7,candidate-8,candidate-9') 'equivalent effects should retain the least total tracking change'

# A figure band can move both lower columns without moving the upper text.
$toPt = 72 / 25.4
$sharedInput = @{
    sharedMinPt=0; sharedMaxPt=5*$toPt
    columns=@(
        @{id='upper'; deltaPt=0; localMinPt=0; localMaxPt=0; sharedCoefficient=0},
        @{id='lower-left'; deltaPt=4.356*$toPt; localMinPt=0; localMaxPt=0; sharedCoefficient=1},
        @{id='lower-right'; deltaPt=5.150*$toPt; localMinPt=0; localMaxPt=0.8*$toPt; sharedCoefficient=1}
    )
}
$sharedPlan = New-JournalSharedBottomPlan $sharedInput
Assert-True ($sharedPlan.status -eq 'ready') 'a common shift and legal local remainder should solve both columns'
Assert-True ([math]::Abs($sharedPlan.sharedDeltaPt - 4.356*$toPt) -lt 0.000001) 'the fixed left column should determine the common shift'
Assert-True ([math]::Abs($sharedPlan.columns[2].localDeltaPt - 0.794*$toPt) -lt 0.000001) 'the right column should receive only its remaining gap'
$sharedInput.columns[2].localMaxPt = 0.5*$toPt
Assert-True ((New-JournalSharedBottomPlan $sharedInput).status -eq 'blocked') 'individually reachable but incompatible column ranges must be rejected'

$opposed = New-JournalSharedBottomPlan @{
    sharedMinPt=-5; sharedMaxPt=5
    columns=@(
        @{id='above'; deltaPt=3; localMinPt=0; localMaxPt=1; sharedCoefficient=-1},
        @{id='below'; deltaPt=-3; localMinPt=-1; localMaxPt=0; sharedCoefficient=1}
    )
}
Assert-True ($opposed.status -eq 'ready' -and $opposed.sharedDeltaPt -eq -2) 'opposite effects should use the feasible shift nearest zero'

$flowSamples=@(
    @{fraction=0; residualMm=-4.33787479986; sameFlow=$true},
    @{fraction=.5; residualMm=-2.16287479986; sameFlow=$true},
    @{fraction=1; residualMm=.01212520014; sameFlow=$true}
)
$fixed=New-JournalFixedFlowFit -Samples $flowSamples
Assert-True ($fixed.status -eq 'ready' -and [math]::Abs($fixed.fraction-.99721259767) -lt .000001) 'fixed line breaks should permit a direct adjustment'
$unstable=New-JournalFixedFlowFit -Samples ($flowSamples + @{fraction=.75; residualMm=0; sameFlow=$false})
Assert-True ($unstable.code -eq 'BOTTOM_FIXED_FLOW_UNSTABLE_BRACKET') 'a changed breakpoint inside the bracket invalidates interpolation'
$flowSamples[1].residualMm=-1
Assert-True ((New-JournalFixedFlowFit -Samples $flowSamples).code -eq 'BOTTOM_FIXED_FLOW_NONLINEAR') 'nonlinear measured responses must not produce a direct plan'

# Given a last-page reference group with an overly broad supplied range.
$column = New-Column 3.6
$column.lastPage = $true
$column.leadingGroups = @([ordered]@{ id='references'; kind='reference'; lineCount=10; currentPt=13; minPt=12; maxPt=14 })
# When the solver applies the journal limit.
$plan = New-JournalBottomPlan -InputObject ([ordered]@{ version=1; tolerancePt=0.01; columns=@($column) })
# Then the leading is clamped to 13 +/- 0.4 pt.
Assert-True ($plan.status -eq 'ready' -and [math]::Abs($plan.columns[0].adjustments[0].toPt-13.4) -lt 0.000001) 'reference leading must clamp at 13.4 pt'

# Given a difference requiring small figure scaling and legal table growth.
$column = New-Column 4.5
$column.figures = @([ordered]@{ id='figure-3'; currentHeightPt=120; currentScalePct=100; minScalePct=98; maxScalePct=103 })
$column.tableRows = @([ordered]@{ id='table-1-row-4'; singleLine=$true; count=1; currentHeightMm=5; minHeightMm=4.8; maxHeightMm=5.5 })
# When earlier stages are insufficient.
$plan = New-JournalBottomPlan -InputObject ([ordered]@{ version=1; tolerancePt=0.01; columns=@($column) })
# Then both object limits are respected.
$figure = @($plan.columns[0].adjustments | Where-Object kind -eq 'figure-height')[0]
$table = @($plan.columns[0].adjustments | Where-Object kind -eq 'table-row-height')[0]
Assert-True ($plan.status -eq 'ready' -and $plan.columns[0].stage -eq 'table') 'table stage should be required'
Assert-True ($figure.toScalePct -le 103) 'figure scaling should remain small'
Assert-True ($table.toMm -ge 4.8 -and $table.toMm -le 5.5) 'table height must remain legal'

# Given an impossible target.
$column = New-Column 50
$column.leadingGroups = @([ordered]@{ id='body-main'; kind='body'; lineCount=2; currentPt=15; minPt=14.8; maxPt=16 })
# When legal capacity is exhausted.
$plan = New-JournalBottomPlan -InputObject ([ordered]@{ version=1; tolerancePt=0.01; columns=@($column) })
# Then it blocks without any blank-space action.
Assert-True ($plan.status -eq 'blocked') 'impossible plan should block'
Assert-True (@($plan.columns[0].adjustments | Where-Object kind -match 'blank|inset|vertical').Count -eq 0) 'blocked plan must not add blank space'

# Given content that extends 3 pt below the target.
$column = New-Column -2.8
$column.leadingGroups = @([ordered]@{ id='body-main'; kind='body'; lineCount=15; currentPt=15; minPt=14.8; maxPt=16 })
# When the solver plans a contraction.
$plan = New-JournalBottomPlan -InputObject ([ordered]@{ version=1; tolerancePt=0.01; columns=@($column) })
# Then it reaches the lower body-leading boundary without a blank-space action.
Assert-True ($plan.status -eq 'ready' -and [math]::Abs($plan.columns[0].adjustments[0].toPt-14.8) -lt 0.000001) 'negative delta should use legal leading contraction'
# Given a request with no explicit tolerance.
$column = New-Column 0.2
$column.leadingGroups = @([ordered]@{ id='body-main'; kind='body'; lineCount=2; currentPt=15; minPt=14.8; maxPt=16 })
# When the solver parses the boundary, then it uses the documented 0.25 pt default.
$plan = New-JournalBottomPlan -InputObject ([ordered]@{ version=1; columns=@($column) })
Assert-True ($plan.tolerancePt -eq 0.25 -and $plan.status -eq 'ready') 'default tolerance should be 0.25 pt'
# Given the same input twice.
$inputObject = [ordered]@{ version=1; tolerancePt=0.01; columns=@($column) }
# When solved twice, then output is deterministic.
Assert-True ((New-JournalBottomPlan -InputObject $inputObject | ConvertTo-Json -Depth 20 -Compress) -ceq (New-JournalBottomPlan -InputObject $inputObject | ConvertTo-Json -Depth 20 -Compress)) 'output must be deterministic'

# Given file input through the public entry point.
$temp = Join-Path ([IO.Path]::GetTempPath()) ('journal-bottom-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp) | Out-Null
try {
    $column = New-Column 6
    $column.leadingGroups = @([ordered]@{ id='body-main'; kind='body'; lineCount=20; currentPt=15; minPt=14.8; maxPt=16; target=[ordered]@{storyRole='body';startIndex=10;endIndex=30} })
    $inputObject = [ordered]@{ version=1; tolerancePt=0.01; columns=@($column) }
    $inputPath = Join-Path $temp 'input.json'; $outputPath = Join-Path $temp 'plan.json'
    [IO.File]::WriteAllText($inputPath,($inputObject|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
    # When the CLI runs, then it writes a ready machine-readable plan.
    & $entryPath -InputPath $inputPath -OutputPath $outputPath | Out-Null
    $cliPlan = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($cliPlan.status -eq 'ready' -and $cliPlan.engine -eq 'journal-bottom-solver') 'CLI should write a ready plan'

    # Given an unsolvable request through the same public entry point.
    $column = New-Column 50
    $column.leadingGroups = @([ordered]@{ id='body-main'; kind='body'; lineCount=2; currentPt=15; minPt=14.8; maxPt=16 })
    [IO.File]::WriteAllText($inputPath,([ordered]@{version=1;tolerancePt=0.01;columns=@($column)}|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
    # When the CLI runs, then it writes diagnostics and raises the queue blocker.
    $didBlock=$false
    try { & $entryPath -InputPath $inputPath -OutputPath $outputPath | Out-Null } catch { $didBlock=$_.Exception.Message -match 'BOTTOM_PLAN_BLOCKED' }
    $cliPlan = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($didBlock -and $cliPlan.status -eq 'blocked') 'CLI must persist diagnostics and block an unsolvable request'
}
finally { Remove-Item -LiteralPath $temp -Recurse -Force }
Write-Output 'PASS offboard bottom solver boundaries, blocking, determinism, and CLI'
