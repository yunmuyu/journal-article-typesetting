param([string]$ImporterPath)

$ErrorActionPreference = "Stop"
if (-not $ImporterPath) {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $importDirectory = @(Get-ChildItem -LiteralPath $projectRoot -Directory | Where-Object Name -like "2-*")[0]
    $ImporterPath = Join-Path $importDirectory.FullName "import_word_article_to_indesign.jsx"
}

$jsonPath = Join-Path $PSScriptRoot "special_glyph_input.json"
$importerSource = [IO.File]::ReadAllText($ImporterPath, [Text.Encoding]::UTF8)
$jsonScriptPath = $jsonPath.Replace('\', '/')
$replacement = 'File("' + $jsonScriptPath + '");'
$importerSource = [regex]::Replace($importerSource, 'File\.openDialog\([^;]*\);', $replacement, 1)

$script = @"
var alert=function(){};
if (app.documents.length===0) throw new Error("Open the real InDesign target document before running this regression.");
var testDocument=app.activeDocument;
var testFrame=null;
var testResult="";
try {
    testFrame=testDocument.textFrames.add();
    testFrame.geometricBounds=[-50,-50,-20,-20];
    app.select(testFrame);
    $importerSource
    var story=testFrame.parentStory;
    testResult=String(story.characters[1].contents)+"|"+
        String(story.characters[4].contents)+"|"+String(story.characters[4].position)+"|"+String(story.characters[4].appliedFont.fontFamily)+"|"+
        String(story.characters[7].contents)+"|"+String(story.characters[7].position)+"|"+
        String(story.characters[8].contents)+"|"+String(story.characters[8].position)+"|"+
        String(story.characters[11].contents)+"|"+String(story.characters[11].position)+"|"+
        String(story.characters[12].contents)+"|"+String(story.characters[12].position)+"|"+
        String(story.characters[13].contents)+"|"+String(story.characters[13].position);
} catch (error) {
    testResult="ERROR|"+String(error)+"|line="+String(error.line);
} finally {
    if (testFrame && testFrame.isValid) testFrame.remove();
}
testResult;
"@

$runningIds = @(Get-Process InDesign -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
if ($runningIds.Count -eq 0) { throw "InDesign 2020 is not already running. Open the target document, then rerun this regression." }
$app = New-Object -ComObject "InDesign.Application.2020"

$result = $app.DoScript($script, 1246973031)
$newIds = @(Get-Process InDesign -ErrorAction SilentlyContinue | Where-Object { $_.Id -notin $runningIds } | Select-Object -ExpandProperty Id)
if ($newIds.Count -gt 0) { throw "Regression unexpectedly started another InDesign process: $($newIds -join ', ')." }
if ($result -like "ERROR|*") { throw $result }
$parts = @($result -split '\|')
if ($parts[0] -ne [string][char]0x3002) { throw "U+FF61 must normalize to U+3002; received '$($parts[0])'." }
if ($parts[1] -ne "2" -or $parts[2] -ne "SUPERSCRIPT") {
    throw "U+00B2 must become a real superscript 2; received '$($parts[1])' at '$($parts[2])'."
}
if ($parts[3] -like "*(OTF)*") { throw "Superscript 2 must not trigger the Times New Roman (OTF) fallback." }
if ($parts[4] -ne "n" -or $parts[5] -ne "SUPERSCRIPT") { throw "U+207F must become a real superscript n." }
if ($parts[6] -ne "+" -or $parts[7] -ne "SUPERSCRIPT") { throw "U+207A must become a real superscript plus." }
if ($parts[8] -ne "1" -or $parts[9] -ne "SUBSCRIPT") { throw "U+2081 must become a real subscript 1." }
if ($parts[10] -ne "-" -or $parts[11] -ne "SUBSCRIPT") { throw "U+208B must become a real subscript minus." }
if ($parts[12] -ne "x" -or $parts[13] -ne "SUBSCRIPT") { throw "U+2093 must become a real subscript x." }

Write-Host "PASS punctuation and unambiguous Unicode super/subscript characters normalize without font fallback."
