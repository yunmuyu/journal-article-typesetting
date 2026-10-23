function Assert-NativeRegressionReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$RunId,
        [Parameter(Mandatory=$true)][datetime]$StartedUtc,
        [Parameter(Mandatory=$true)][string]$SourceSha256,
        [AllowEmptyString()][string]$ScriptResult
    )
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){throw 'NATIVE_REPORT_MISSING'}
    $item=Get-Item -LiteralPath $Path
    if($item.LastWriteTimeUtc -lt $StartedUtc.AddSeconds(-2)){throw 'NATIVE_REPORT_STALE_TIME'}
    $result=Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json
    if($result.run_id -cne $RunId){throw 'NATIVE_REPORT_RUN_ID_MISMATCH'}
    if(-not $result.started_utc -or ([datetime]$result.started_utc).ToUniversalTime().Ticks -ne $StartedUtc.ToUniversalTime().Ticks){throw 'NATIVE_REPORT_STARTED_TIME_MISMATCH'}
    if($result.source_sha256 -cne $SourceSha256){throw 'NATIVE_REPORT_SOURCE_SHA_MISMATCH'}
    if(-not $result.passed){throw ($result | ConvertTo-Json -Compress)}
    if($ScriptResult -cne $RunId){throw 'NATIVE_EXECUTION_ID_MISMATCH'}
    return $result
}
Export-ModuleMember -Function Assert-NativeRegressionReport
