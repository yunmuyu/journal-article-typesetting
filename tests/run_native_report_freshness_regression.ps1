$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'NativeRegressionReport.psm1') -Force
$root=Join-Path $env:TEMP ('journal-report-freshness-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
try{
    $old=Join-Path $root 'old.json'
    $started=[DateTime]::UtcNow
    [IO.File]::WriteAllText($old,'{"passed":true,"run_id":"old","started_utc":"2020-01-01T00:00:00Z","source_sha256":"old"}')
    [IO.File]::SetLastWriteTimeUtc($old,$started.AddMinutes(-5))
    $expected=@{Path=$old;RunId='new';StartedUtc=$started;SourceSha256='new';ScriptResult='new'}
    try{Assert-NativeRegressionReport @expected | Out-Null;throw 'STALE_REPORT_ACCEPTED'}catch{if($_.Exception.Message -eq 'STALE_REPORT_ACCEPTED'){throw}}
    $expected.RunId='old';$expected.ScriptResult='old';$expected.SourceSha256='old'
    try{Assert-NativeRegressionReport @expected | Out-Null;throw 'OLD_TIMESTAMP_ACCEPTED'}catch{if($_.Exception.Message -eq 'OLD_TIMESTAMP_ACCEPTED'){throw}}
    $fresh=Join-Path $root 'fresh.json'
    [IO.File]::WriteAllText($fresh,('{"passed":true,"run_id":"new","started_utc":"'+($started.ToString('o'))+'","source_sha256":"new"}'))
    $expected.Path=$fresh;$expected.RunId='new';$expected.ScriptResult='new';$expected.SourceSha256='new'
    Assert-NativeRegressionReport @expected | Out-Null
    $expected.SourceSha256='wrong'
    try{Assert-NativeRegressionReport @expected | Out-Null;throw 'WRONG_SOURCE_ACCEPTED'}catch{if($_.Exception.Message -eq 'WRONG_SOURCE_ACCEPTED'){throw}}
    $expected.SourceSha256='new'
    $expected.ScriptResult='wrong'
    try{Assert-NativeRegressionReport @expected | Out-Null;throw 'WRONG_EXECUTION_ACCEPTED'}catch{if($_.Exception.Message -eq 'WRONG_EXECUTION_ACCEPTED'){throw}}
    'PASS stale, mismatched execution and fresh native reports'
}finally{Get-ChildItem -LiteralPath $root -File | Remove-Item -Force;Remove-Item -LiteralPath $root}
