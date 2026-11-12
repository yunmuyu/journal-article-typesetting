param([switch]$WithWindowsTypography)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'run_offline_layout_solver_regression.ps1')
& node --test (Join-Path $PSScriptRoot 'offline_measured_advance.test.cjs')
if ($LASTEXITCODE -ne 0) { throw 'MEASURED_ADVANCE_REGRESSION_FAILED' }
if ($WithWindowsTypography) {
    & (Join-Path $PSScriptRoot 'run_offline_body_prediction_regression.ps1')
} else {
    Write-Host 'Windows typography tests not requested; native Adobe validation not run.'
}
