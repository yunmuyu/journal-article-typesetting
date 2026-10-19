param([string]$ImporterPath)
$ErrorActionPreference = 'Stop'
if (-not $ImporterPath) {
    $ImporterPath = Join-Path (Split-Path -Parent $PSScriptRoot) '2-导入_InDesign\import_word_article_to_indesign.jsx'
}
$jsonPath = (Join-Path $PSScriptRoot 'script_italic_input.json').Replace('\','/')
$source = [IO.File]::ReadAllText($ImporterPath, [Text.Encoding]::UTF8)
$source = [regex]::Replace($source, 'File\.openDialog\([^;]*\);', ('File("'+$jsonPath+'");'), 1)
$app = New-Object -ComObject 'InDesign.Application.2020'
foreach ($mode in @('template', 'missing', 'disabled')) {
    $testSource = $source
    if ($mode -eq 'missing') {
        $testSource = [regex]::Replace($testSource, 'characterStyles: \{[^\r\n]+', 'characterStyles: {italic:["__missing_italic__"],bold:["__missing_bold__"],sup:["__missing_sup__"],sub:["__missing_sub__"],authorBioLabel:["__missing_bio__"]},')
    } elseif ($mode -eq 'disabled') {
        $testSource = $testSource.Replace('disabledCharacterStyles: {}', 'disabledCharacterStyles: {"斜体":true,"上标":true,"下标":true}')
    }
    $script = @"
var alert=function(){};
var d=app.activeDocument, frame=null, result="";
try {
    var sub=d.characterStyles.itemByName("下标");
    if (!sub.isValid) sub=d.characterStyles.add({name:"下标",appliedFont:app.fonts.itemByName("Times New Roman\tRegular"),fontStyle:"Regular",position:Position.SUBSCRIPT});
    frame=d.textFrames.add({geometricBounds:[20,20,120,180]});
    app.select(frame);
    $testSource
    var expectedPositions=[Position.NORMAL,Position.SUPERSCRIPT,Position.SUPERSCRIPT,Position.SUPERSCRIPT,Position.SUBSCRIPT,Position.SUBSCRIPT,Position.SUBSCRIPT];
    var expectedFaces=["Italic","Italic","Bold Italic","Italic","Italic","Bold Italic"];
    var story=frame.parentStory;
    for(var i=0;i<7;i++) {
        var c=story.characters[i];
        if(c.position!==expectedPositions[i]) throw new Error("position "+i+" received "+c.position);
        if(i<6 && (c.fontStyle!==expectedFaces[i] || c.appliedFont.fontFamily!=="Times New Roman" || c.appliedFont.status!==FontStatus.INSTALLED)) throw new Error("font "+i+" received "+c.appliedFont.name+" "+c.fontStyle);
        if(i===6 && /Italic/.test(c.fontStyle)) throw new Error("numeric subscript became italic");
    }
    if(String(story.contents)!=="XCHWβZ2\r   \rafter\r") throw new Error("blank location changed: "+story.contents);
    if(story.paragraphs[1].justification!==Justification.LEFT_ALIGN || story.paragraphs[1].firstLineIndent!==0) throw new Error("table gap must be left aligned without first-line indent");
    for(var j=12;j<17;j++) if(story.characters[j].fontStyle!=="Italic") throw new Error("offset after gap "+j);
    result="PASS|$mode";
} catch(e) { result="ERROR|"+e+"|line="+e.line; }
finally { if(frame && frame.isValid) frame.remove(); }
result;
"@
    $result = $app.DoScript($script, 1246973031)
    if ($result -ne "PASS|$mode") { throw $result }
    Write-Host $result
}
