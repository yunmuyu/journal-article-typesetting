param([string]$ConverterPath)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not $ConverterPath) {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $extractorDirectory = @(Get-ChildItem -LiteralPath $projectRoot -Directory | Where-Object Name -like "1-*")[0]
    $ConverterPath = Join-Path $extractorDirectory.FullName "docx_to_id_json.ps1"
}

$workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("word-to-indesign-format-test-" + [Guid]::NewGuid().ToString("N"))
[System.IO.Directory]::CreateDirectory($workDir) | Out-Null

try {
    $docxPath = Join-Path $workDir "greek-subscript.docx"
    $jsonPath = Join-Path $workDir "greek-subscript.json"
    $documentXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
<w:p><w:r><w:t>0 &#x5F15;&#x8A00;</w:t></w:r></w:p>
<w:p><w:r><w:rPr><w:i/></w:rPr><w:t>F</w:t></w:r><w:r><w:rPr><w:i/><w:vertAlign w:val="subscript"/></w:rPr><w:t>β</w:t></w:r><w:r><w:t xml:space="preserve"> x</w:t></w:r><w:r><w:rPr><w:i/><w:vertAlign w:val="subscript"/></w:rPr><w:t>2</w:t></w:r></w:p>
</w:body></w:document>
'@
    $archive = [System.IO.Compression.ZipFile]::Open($docxPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $entry = $archive.CreateEntry("word/document.xml")
        $writer = New-Object System.IO.StreamWriter($entry.Open(), (New-Object System.Text.UTF8Encoding $false))
        try { $writer.Write($documentXml) } finally { $writer.Dispose() }
    } finally { $archive.Dispose() }

    & $ConverterPath -DocxPath $docxPath -OutputPath $jsonPath

    $body = @((Get-Content -Raw -LiteralPath $jsonPath | ConvertFrom-Json).blocks | Where-Object role -eq "body")[0]
    $beta = @($body.runs | Where-Object { $_.start -eq 1 -and $_.end -eq 2 })[0]
    if ($beta.position -ne "subscript" -or -not $beta.italic) {
        throw "Greek subscript beta must retain both subscript and italic formatting."
    }

    $numeric = @($body.runs | Where-Object { $_.start -eq 4 -and $_.end -eq 5 })[0]
    if ($numeric.position -ne "subscript" -or $numeric.italic) {
        throw "Numeric subscript must remain upright while retaining subscript formatting."
    }

    Write-Host "PASS Greek-letter subscript italics are preserved."
} finally {
    if (Test-Path -LiteralPath $workDir) { Remove-Item -LiteralPath $workDir -Recurse -Force }
}
