param([string]$ImporterPath)

$ErrorActionPreference = "Stop"
if (-not $ImporterPath) {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $importDirectory = @(Get-ChildItem -LiteralPath $projectRoot -Directory | Where-Object Name -like "2-*")[0]
    $ImporterPath = Join-Path $importDirectory.FullName "import_word_article_to_indesign.jsx"
}

$jsonPath = Join-Path $PSScriptRoot "superscript_leading_input.json"
$importerSource = [IO.File]::ReadAllText($ImporterPath, [Text.Encoding]::UTF8)
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
    var italicStyle=testDocument.characterStyles.itemByName("\u659c\u4f53");
    if (!italicStyle.isValid) throw new Error("The active target document has no italic character style.");
    testFrame=testDocument.textFrames.add();
    testFrame.geometricBounds=[-50,-50,-20,-20];
    app.select(testFrame);
    $importerSource
    var story=testFrame.parentStory;
    var rows=[];
    for (var characterIndex=0; characterIndex<5; characterIndex++) {
        var character=story.characters[characterIndex];
        rows.push(
            String(character.contents)+"|"+
            String(character.position)+"|"+
            String(character.pointSize)+"|"+
            String(character.leading)+"|"+
            String(character.appliedFont.fontFamily)+"|"+
            String(character.fontStyle)
        );
    }
    testResult=rows.join("~");
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
$rows = @($result -split '~')

foreach ($index in 0..4) {
    $parts = @($rows[$index] -split '\|')
    if ($parts[1] -ne "SUPERSCRIPT") {
        throw "Character '$($parts[0])' must remain superscript; received position '$($parts[1])'."
    }
    if ($parts[2] -ne "10.5" -or $parts[3] -ne "15") {
        throw "Character '$($parts[0])' must remain 10.5 pt with 15 pt leading; received size '$($parts[2])' and leading '$($parts[3])'."
    }
}

foreach ($index in 0,2) {
    $parts = @($rows[$index] -split '\|')
    if ($parts[4] -ne "Times New Roman" -or $parts[5] -ne "Italic") {
        throw "Italic superscript '$($parts[0])' must use Times New Roman Italic; received '$($parts[4]) $($parts[5])'."
    }
}

Write-Host "PASS Italic H/W remain superscript at 10.5 pt with 15 pt leading."
