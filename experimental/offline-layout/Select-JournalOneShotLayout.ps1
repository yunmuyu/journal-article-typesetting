#Requires -Version 7.0
param(
    [Parameter(Mandatory)][string[]]$CandidatePaths,
    [Parameter(Mandatory)][string]$ReportPath
)
$ErrorActionPreference = 'Stop'
$solver = Join-Path $PSScriptRoot 'Find-MeasuredPageWindow.ps1'
$check = Join-Path $PSScriptRoot 'Test-JournalLayoutRobustness.ps1'
. (Join-Path $PSScriptRoot 'Read-PageWindowInput.ps1')
$candidates = @(foreach ($path in $CandidatePaths) {
    $inputPath = (Resolve-Path -LiteralPath $path).Path
    $hash = (Get-FileHash -LiteralPath $inputPath).Hash
    $data = Read-PageWindowInput $inputPath -RequireUncertainty
    $plan = & $solver -MeasurementPath $inputPath
    $review = if ($plan.status -eq 'ready-for-native-check') {
        & $check -MeasurementPath $inputPath -Plan $plan | ConvertFrom-Json -Depth 100
    }
    if ((Get-FileHash -LiteralPath $inputPath).Hash -ne $hash) { throw "LAYOUT_INPUT_CHANGED $inputPath" }
    [pscustomobject]@{
        path = $inputPath; sha256 = $hash; sourceIdentity = $data.sourceIdentity
        startIndex = $data.startIndex; endIndex = $data.endIndex; plan = $plan; review = $review
        status = if ($review) { $review.status } else { $plan.status }
        changeMm = ($plan.placements | ForEach-Object { [math]::Abs($_.adjustmentMm) } | Measure-Object -Sum).Sum
    }
})
$first = $candidates[0]
foreach ($candidate in $candidates) {
    if (![string]::Equals($candidate.sourceIdentity, $first.sourceIdentity, [StringComparison]::Ordinal) -or
        $candidate.startIndex -ne $first.startIndex -or $candidate.endIndex -ne $first.endIndex) {
        throw 'LAYOUT_CANDIDATES_REQUIRE_SAME_SOURCE_RANGE'
    }
}
$winner = $candidates | Where-Object status -eq 'robust-under-supplied-bounds' |
    Sort-Object changeMm, sha256 | Select-Object -First 1
$result = [ordered]@{
    status = if ($winner) { 'one-offline-plan-selected' } else { 'no-robust-offline-plan' }
    adobeCalls = 0; selected = $winner; candidates = $candidates
}
$stream = [IO.File]::Open([IO.Path]::GetFullPath($ReportPath), [IO.FileMode]::CreateNew)
try {
    $writer = [IO.StreamWriter]::new($stream)
    try { $writer.Write(($result | ConvertTo-Json -Depth 30)) } finally { $writer.Dispose() }
} finally { $stream.Dispose() }
$result.status
