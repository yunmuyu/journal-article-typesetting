param([string]$ImporterPath)

$ErrorActionPreference = "Stop"
if (-not $ImporterPath) {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $importDirectory = @(Get-ChildItem -LiteralPath $projectRoot -Directory | Where-Object Name -like "2-*")[0]
    $ImporterPath = Join-Path $importDirectory.FullName "import_word_article_to_indesign.jsx"
}

$jsonPath = Join-Path $PSScriptRoot "inherited_character_style_input.json"
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
    var inheritedStyle=testDocument.characterStyles.itemByName("\u9ed1\u4f53");
    if (!inheritedStyle.isValid) throw new Error("The active target document has no black character style.");
    testFrame=testDocument.textFrames.add();
    testFrame.geometricBounds=[-50,-50,-20,-20];
    testFrame.parentStory.insertionPoints[0].appliedCharacterStyle=inheritedStyle;
    app.select(testFrame);
    $importerSource
    var story=testFrame.parentStory;
    var referenceParagraph=story.paragraphs[1];
    var authorParagraph=story.paragraphs[2];
    var referenceCharacter=referenceParagraph.characters[4];
    var authorCharacter=authorParagraph.characters[5];
    testResult=[
        referenceParagraph.appliedParagraphStyle.name,
        referenceCharacter.appliedCharacterStyle.name,
        referenceCharacter.appliedFont.fontFamily,
        referenceCharacter.fontStyle,
        referenceCharacter.pointSize,
        referenceCharacter.leading,
        authorParagraph.appliedParagraphStyle.name,
        authorCharacter.appliedCharacterStyle.name,
        authorCharacter.appliedFont.fontFamily,
        authorCharacter.fontStyle,
        authorCharacter.pointSize,
        authorCharacter.leading
    ].join("|");
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

$parts = @($result -split '\|')
$noneStyle = "[" + [char]0x65E0 + "]"
$referenceParagraphStyle = -join @([char]0x53C2, [char]0x8003, [char]0x6587, [char]0x732E, " ", [char]0x5185, [char]0x5BB9)
$bodyFont = -join @([char]0x73B0, " ", [char]0x5B8B, [char]0x4F53, "-1")
$authorParagraphStyle = -join @([char]0x4F5C, [char]0x8005, [char]0x7B80, [char]0x4ECB)
$authorFont = -join @([char]0x6977, [char]0x4F53)

if ($parts[0] -ne $referenceParagraphStyle) {
    throw "Reference paragraph style changed to '$($parts[0])'."
}
if ($parts[1] -ne $noneStyle -or $parts[2] -ne $bodyFont -or $parts[3] -ne "Regular" -or $parts[4] -ne "9" -or $parts[5] -ne "13") {
    throw "Reference content inherited '$($parts[1])' and rendered as '$($parts[2]) $($parts[3])' at $($parts[4])/$($parts[5]); expected the paragraph style font at 9/13."
}
if ($parts[6] -ne $authorParagraphStyle) {
    throw "Author bio paragraph style changed to '$($parts[6])'."
}
if ($parts[7] -ne $noneStyle -or $parts[8] -ne $authorFont -or $parts[9] -ne "Regular" -or $parts[10] -ne "9" -or $parts[11] -ne "13") {
    throw "Author bio body inherited '$($parts[7])' and rendered as '$($parts[8]) $($parts[9])' at $($parts[10])/$($parts[11]); expected the paragraph style font at 9/13."
}

Write-Host "PASS Reference and author bio fonts come from their paragraph styles without inherited character styles."
