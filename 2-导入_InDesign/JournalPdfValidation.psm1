function Test-JournalPdfRender {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PdfPath,
        [Parameter(Mandatory)][string]$PythonExe,
        [Parameter(Mandatory)][string]$ValidatorPath
    )
    $ErrorActionPreference = 'Stop'
    if (!(Test-Path -LiteralPath $ValidatorPath -PathType Leaf)) { throw 'PDF_RENDER_VALIDATOR_REQUIRED' }
    $raw = & $PythonExe -I $ValidatorPath $PdfPath
    $exitCode = $LASTEXITCODE
    try { $report = ($raw -join "`n") | ConvertFrom-Json } catch { throw 'PDF_RENDER_REPORT_INVALID' }
    if ($exitCode -ne 0 -or $report.passed -isnot [bool] -or !$report.passed) {
        throw "PDF_RENDER_FAILED $($report.error)"
    }
    if ($report.page_count -isnot [long] -and $report.page_count -isnot [int]) { throw 'PDF_RENDER_COUNT_INVALID' }
    if ($report.page_count -lt 1 -or $report.rendered_pages -ne $report.page_count) { throw 'PDF_RENDER_INCOMPLETE' }
    return $report
}
Export-ModuleMember -Function Test-JournalPdfRender
