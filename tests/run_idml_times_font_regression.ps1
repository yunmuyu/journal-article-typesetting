$ErrorActionPreference = 'Stop'
$tool = Join-Path $PSScriptRoot '../2-导入_InDesign/Repair-JournalIdmlTimesFont.ps1'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('journal-font-test-' + [guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($temp)

function New-Fixture([string]$Name, [string]$Status) {
    $path = Join-Path $temp $Name
    $archive = [IO.Compression.ZipFile]::Open($path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $parts = @{
            'Resources/Fonts.xml' = @"
<Fonts><FontFamily Name="Times New Roman (OTF)"><Font FontStyleName="Italic" PostScriptName="TimesNewRomanPS-ItalicMT" Status="NotAvailable"/></FontFamily><FontFamily Name="Times New Roman"><Font FontStyleName="Italic" PostScriptName="TimesNewRomanPS-ItalicMT" Status="$Status"/></FontFamily></Fonts>
"@
            'Stories/Story_fixture.xml' = '<Story><CharacterStyleRange FontStyle="Italic" AppliedFont="Times New Roman (OTF)"><Content>Times New Roman (OTF)</Content></CharacterStyleRange></Story>'
        }
        foreach ($entry in $parts.GetEnumerator()) {
            $writer = [IO.StreamWriter]::new($archive.CreateEntry($entry.Key).Open())
            try { $writer.Write($entry.Value) } finally { $writer.Dispose() }
        }
    } finally { $archive.Dispose() }
    return $path
}

try {
    $source = New-Fixture 'source.idml' 'Installed'
    $originalHash = (Get-FileHash -LiteralPath $source).Hash
    $output = Join-Path $temp 'corrected-QA.idml'
    $result = & $tool -SourcePath $source -OutputPath $output
    if ($result.fontReferencesUpdated -ne 1 -or (Get-FileHash -LiteralPath $source).Hash -ne $originalHash) {
        throw 'EXPECTED_ONE_REFERENCE_AND_UNCHANGED_SOURCE'
    }
    $archive = [IO.Compression.ZipFile]::OpenRead($output)
    try {
        $reader = [IO.StreamReader]::new($archive.GetEntry('Stories/Story_fixture.xml').Open())
        try { [xml]$story = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $range = $story.Story.CharacterStyleRange
        if ($range.AppliedFont -cne 'Times New Roman' -or $range.FontStyle -cne 'Italic' -or
            $range.Content -cne 'Times New Roman (OTF)') { throw 'FONT_REPAIR_CHANGED_CONTENT_OR_FACE' }
    } finally { $archive.Dispose() }

    $missing = New-Fixture 'missing.idml' 'NotAvailable'
    $rejected = Join-Path $temp 'rejected-QA.idml'
    try { & $tool -SourcePath $missing -OutputPath $rejected; throw 'UNVERIFIED_FONT_ACCEPTED' }
    catch { if ($_.Exception.Message -ne 'TIMES_FONT_MAPPING_UNVERIFIED') { throw } }
    if (Test-Path -LiteralPath $rejected) { throw 'UNVERIFIED_OUTPUT_WRITTEN' }
    'PASS exact Times font face mapping, source integrity and failed-match rejection'
} finally {
    Get-ChildItem -LiteralPath $temp -File | Remove-Item
    Remove-Item -LiteralPath $temp
}
