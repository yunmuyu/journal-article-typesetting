$ErrorActionPreference = 'Stop'
$extractor = Join-Path (Split-Path -Parent $PSScriptRoot) '1-提取_Word转JSON\docx_to_id_json.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($extractor, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Extractor syntax invalid.' }
$conversion = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Convert-DocToDocx' }, $true)
$conversionTry = $conversion.Body.Find({ param($node) $node -is [System.Management.Automation.Language.TryStatementAst] -and $node.Finally }, $true)
$sentinel = $null
try {
    # Given: an unrelated process; redirect global WINWORD queries to this owned test process.
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $startInfo.Arguments = '-NoProfile -Command "Start-Sleep -Seconds 120"'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $sentinel = [System.Diagnostics.Process]::Start($startInfo)
    function Get-Process {
        param([string]$Name)
        if ($Name -ne 'WINWORD') { throw "Unexpected lookup: $Name" }
        Microsoft.PowerShell.Management\Get-Process -Id $sentinel.Id
    }
    # When: execute the extractor's actual cleanup without creating a Word COM instance.
    $word = $null
    & ([scriptblock]::Create($conversionTry.Finally.Extent.Text.Trim().TrimStart('{').TrimEnd('}')))
    # Then: cleanup preserves the unrelated process, including after initialization fails.
    $sentinel.Refresh()
    if ($sentinel.HasExited) { throw 'Word cleanup killed an unrelated process.' }
    Write-Output 'PASS Word cleanup preserves unrelated processes.'
} finally {
    if ($sentinel) {
        $sentinel.Refresh()
        if (-not $sentinel.HasExited) { $sentinel.Kill() }
        $sentinel.Dispose()
    }
}
