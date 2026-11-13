#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourcePath,
    [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$source = (Get-Item -LiteralPath $SourcePath).FullName
$output = [IO.Path]::GetFullPath($OutputPath)
if ($source -notmatch '\.idml$' -or $output -notmatch 'QA\.idml$' -or
    (Test-Path -LiteralPath $output)) { throw 'TIMES_FONT_QA_OUTPUT_REQUIRED' }

$temp = Join-Path ([IO.Path]::GetDirectoryName($output)) ('.font-' + [guid]::NewGuid() + '.idml')
$alias = 'Times New Roman (OTF)'
$family = 'Times New Roman'
$faces = @{
    'Regular' = 'TimesNewRomanPSMT'
    'Italic' = 'TimesNewRomanPS-ItalicMT'
    'Bold' = 'TimesNewRomanPS-BoldMT'
    'Bold Italic' = 'TimesNewRomanPS-BoldItalicMT'
}

function Read-PackageXml($Entry) {
    $settings = [Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $stream = $Entry.Open()
    try {
        $reader = [Xml.XmlReader]::Create($stream, $settings)
        try {
            $document = [Xml.XmlDocument]::new()
            $document.PreserveWhitespace = $true
            $document.Load($reader)
            return ,$document
        } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
}

function Write-PackageXml($Archive, $Entry, $Document) {
    $name = $Entry.FullName
    $Entry.Delete()
    $stream = $Archive.CreateEntry($name).Open()
    try { $Document.Save($stream) } finally { $stream.Dispose() }
}

try {
    [IO.File]::Copy($source, $temp)
    $archive = [IO.Compression.ZipFile]::Open($temp, [IO.Compression.ZipArchiveMode]::Update)
    $updated = 0
    try {
        $fontsEntry = $archive.GetEntry('Resources/Fonts.xml')
        if (!$fontsEntry) { throw 'TIMES_FONT_RESOURCE_MISSING' }
        $fonts = Read-PackageXml $fontsEntry
        $legacy = $fonts.SelectSingleNode("//FontFamily[@Name='$alias']")
        if ($legacy) {
            $available = $fonts.SelectSingleNode("//FontFamily[@Name='$family']")
            if (!$available -or !$legacy.SelectNodes('./Font').Count) { throw 'TIMES_FONT_MAPPING_UNVERIFIED' }
            foreach ($font in $legacy.SelectNodes('./Font')) {
                $face = $font.GetAttribute('FontStyleName')
                $postScript = $font.GetAttribute('PostScriptName')
                $match = $available.SelectNodes("./Font[@Status='Installed']") |
                    Where-Object { $_.GetAttribute('FontStyleName') -ceq $face -and $_.GetAttribute('PostScriptName') -ceq $postScript }
                if ($font.GetAttribute('Status') -cne 'NotAvailable' -or
                    !$faces.ContainsKey($face) -or $faces[$face] -cne $postScript -or
                    @($match).Count -ne 1) { throw 'TIMES_FONT_MAPPING_UNVERIFIED' }
            }
            foreach ($entry in @($archive.Entries | Where-Object { $_.FullName -like '*.xml' -and $_.FullName -ne $fontsEntry.FullName })) {
                $document = Read-PackageXml $entry
                $nodes = $document.SelectNodes("//*[local-name()='AppliedFont' and text()='$alias'] | //@AppliedFont[.='$alias']")
                if (!$nodes.Count) { continue }
                foreach ($node in $nodes) { $node.InnerText = $family }
                $updated += $nodes.Count
                Write-PackageXml $archive $entry $document
            }
            $null = $legacy.ParentNode.RemoveChild($legacy)
            Write-PackageXml $archive $fontsEntry $fonts
        }
    } finally { $archive.Dispose() }
    [IO.File]::Move($temp, $output)
    [pscustomobject]@{ outputPath = $output; fontReferencesUpdated = $updated }
} finally {
    if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
}
