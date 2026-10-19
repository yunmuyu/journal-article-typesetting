param([Parameter(Mandatory=$true)][string]$DocPath)
$ErrorActionPreference = 'Stop'
$bat = Join-Path (Split-Path -Parent $PSScriptRoot) '1-提取_Word转JSON\Word转JSON-拖这里.bat'
$testRoot = Join-Path $env:TEMP ('w2id-doc-regression-' + [Guid]::NewGuid().ToString('N'))
$oldPause = $env:W2ID_NO_PAUSE
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    # Given: an isolated legacy input and the user's existing Word processes.
    $inputPath = Join-Path $testRoot '[table] article % !.doc'
    Copy-Item -LiteralPath $DocPath -Destination $inputPath
    $beforeBytes = [System.IO.File]::ReadAllBytes($inputPath)
    $wordProcesses = @(Microsoft.PowerShell.Management\Get-Process WINWORD -ErrorAction SilentlyContinue)
    $env:W2ID_NO_PAUSE = '1'
    # When: use the real drag-and-drop BAT, which launches Windows PowerShell 5.1.
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $env:ComSpec
    $startInfo.Arguments = '/d /s /c ""' + $bat + '" "' + $inputPath + '""'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($startInfo)
    try {
        if (-not $process.WaitForExit(30000)) { throw 'Legacy BAT timed out.' }
        if ($process.ExitCode -ne 0) { throw 'Legacy BAT conversion failed.' }
    } finally { $process.Dispose() }
    # Then: conversion finishes, produces text, preserves input and leaves existing Word processes alive.
    $outputPath = [System.IO.Path]::ChangeExtension($inputPath, '.json')
    $article = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($article.blocks.Count -eq 0) { throw 'Legacy BAT produced no article blocks.' }
    $afterBytes = [System.IO.File]::ReadAllBytes($inputPath)
    if ([Convert]::ToBase64String($beforeBytes) -cne [Convert]::ToBase64String($afterBytes)) { throw 'Legacy source was modified.' }
    foreach ($process in $wordProcesses) {
        $process.Refresh()
        if ($process.HasExited) { throw "Existing Word process closed: $($process.Id)" }
    }
    Write-Output "PASS real legacy BAT: $($article.blocks.Count) blocks; original bytes and existing Word processes preserved."
} finally {
    $env:W2ID_NO_PAUSE = $oldPause
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    if (-not $resolvedTestRoot.StartsWith([System.IO.Path]::GetFullPath($env:TEMP) + '\', [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected cleanup path.' }
    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
}
