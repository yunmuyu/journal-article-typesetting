param(
    [Parameter(Mandatory=$true)][string]$DocumentPath,
    [Parameter(Mandatory=$true)][string]$ManifestPath,
    [int[]]$ReferencePages = @(29,30,31,32,33,34),
    [double]$LeftPageLeftMm = 14.5,
    [double]$RightPageLeftMm = 17.5,
    [double]$ColumnWidthMm = 85.5,
    [double]$ColumnGapMm = 7,
    [double]$SpreadWidthMm = 178,
    [string]$TemplateContractVersion = 'issue-continuation-v1',
    [switch]$PlanOnly
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'JournalInDesignScript.psm1') -Force
$document = (Get-Item -LiteralPath $DocumentPath).FullName
$manifest = [IO.Path]::GetFullPath($ManifestPath)
if ([IO.Path]::GetFileName($document) -notmatch '(?i)QA|copy|副本') { throw 'SEED_REQUIRES_QA_COPY' }
$geometry = [ordered]@{
    leftPageLeftMm = $LeftPageLeftMm
    rightPageLeftMm = $RightPageLeftMm
    columnWidthMm = $ColumnWidthMm
    columnGapMm = $ColumnGapMm
    spreadWidthMm = $SpreadWidthMm
}
$job = [ordered]@{
    path = $document
    referencePages = @($ReferencePages)
    geometry = $geometry
    templateContractVersion = $TemplateContractVersion
}
if ($PlanOnly) { $job | ConvertTo-Json -Depth 6; return }
if (Test-Path -LiteralPath $manifest) { throw 'SEED_MANIFEST_EXISTS' }
$beforeHash = (Get-FileHash -LiteralPath $document -Algorithm SHA256).Hash.ToLowerInvariant()
$jsx = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'seed_issue_article_pages.jsx'), [Text.Encoding]::UTF8)
$resultPath = $manifest + '.native.txt'
if (Test-Path -LiteralPath $resultPath) { Remove-Item -LiteralPath $resultPath -Force }
$job.resultPath = $resultPath
$jobJson = $job | ConvertTo-Json -Depth 6 -Compress
$application = New-Object -ComObject 'InDesign.Application.2020'
$code = "var JournalSeedJob=$jobJson;`n" + $jsx
[void](Invoke-JournalInDesignScript -Application $application -Code $code)
if (-not (Test-Path -LiteralPath $resultPath)) { throw 'SEED_NO_RESULT_FILE' }
$result = [IO.File]::ReadAllText($resultPath, [Text.Encoding]::UTF8)
if ($result -notmatch '(?m)^BEFORE ') { throw "SEED_FAILED $result" }
if ($result -match '(?m)^ERROR ') { throw "SEED_FAILED $result" }
$afterHash = (Get-FileHash -LiteralPath $document -Algorithm SHA256).Hash.ToLowerInvariant()
$record = [ordered]@{
    schemaVersion = 1
    documentPath = $document
    documentSha256Before = $beforeHash
    documentSha256After = $afterHash
    referencePages = @($ReferencePages)
    geometry = $geometry
    templateContractVersion = $TemplateContractVersion
    createdPages = @($result -split "`n" | Where-Object { $_ -match '^CREATED ' } | ForEach-Object { $_ -replace '^CREATED ', '' } |
        ForEach-Object { $_ -split ';' } | Where-Object { $_ } | ForEach-Object {
            $parts = $_ -split ','
            [ordered]@{ index = [int]$parts[0]; name = $parts[1]; side = $parts[2]; master = $parts[3]; frames = [int]$parts[4] }
        })
    bodyChain = [int](@($result -split "`n" | Where-Object { $_ -match '^BODYCHAIN ' })[0] -replace '^BODYCHAIN ', '')
    createdAt = [DateTime]::UtcNow.ToString('o')
    rawResult = $result
}
$parent = Split-Path -Parent $manifest
if ($parent) { [void][IO.Directory]::CreateDirectory($parent) }
[IO.File]::WriteAllText($manifest, ($record | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
$record | ConvertTo-Json -Depth 6
