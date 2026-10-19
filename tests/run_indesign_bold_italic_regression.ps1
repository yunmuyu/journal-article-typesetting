param([string]$ImporterPath)

$ErrorActionPreference = "Stop"
if (-not $ImporterPath) {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $importDirectory = @(Get-ChildItem -LiteralPath $projectRoot -Directory | Where-Object Name -like "2-*")[0]
    $ImporterPath = Join-Path $importDirectory.FullName "import_word_article_to_indesign.jsx"
}

$jsonPath = Join-Path $PSScriptRoot "bold_italic_input.json"
$importerSource = [IO.File]::ReadAllText($ImporterPath, [Text.Encoding]::UTF8)
$directFaceIndex = $importerSource.IndexOf("var bi=findInstalledFont(CONFIG.fallbackBoldItalicFontNames);")
$genericFaceIndex = $importerSource.IndexOf('var tnr=findInstalledFont(["Times New Roman"', $directFaceIndex)

if ($directFaceIndex -lt 0 -or $genericFaceIndex -lt 0 -or $directFaceIndex -gt $genericFaceIndex) {
    throw "Bold Italic must prefer the exact installed face before the generic Times family fallback."
}

$jsonScriptPath = $jsonPath.Replace('\', '/')
$replacement = 'File("' + $jsonScriptPath + '");'
$importerSource = [regex]::Replace(
    $importerSource,
    'File\.openDialog\([^;]*\);',
    $replacement,
    1
)

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
    var fontResults=[];
    for (var characterIndex=0; characterIndex<2; characterIndex++) {
        var testChar=testFrame.parentStory.characters[characterIndex];
        fontResults.push(String(testChar.appliedFont.name)+"|"+String(testChar.appliedFont.fontType)+"|"+String(testChar.appliedFont.location)+"|"+String(testChar.fontStyle));
    }
    testResult=String(testFrame.contents).replace(/\r/g,"")+"|"+fontResults.join("||");
} catch (error) {
    testResult="ERROR|"+String(error)+"|line="+String(error.line);
} finally {
    if (testFrame && testFrame.isValid) testFrame.remove();
}
testResult;
"@

$app = New-Object -ComObject "InDesign.Application.2020"
$result = $app.DoScript($script, 1246973031)
if ($result -like "ERROR|*") {
    throw $result
}
$expectedFont = "Times New Roman" + [char]9 + "Bold Italic|TRUETYPE|C:\WINDOWS\Fonts\timesbi.ttf|Bold Italic"
$expected = "RM|$expectedFont||$expectedFont"

if ($result -ne $expected) {
    throw "Expected '$expected', received '$result'."
}

Write-Host "PASS Bold Italic uses the exact TrueType Times New Roman face."
