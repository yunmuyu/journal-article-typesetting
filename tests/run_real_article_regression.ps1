param(
    [Parameter(Mandatory=$true)][string]$DocxPath,
    [string]$PythonPath,
    [string]$ImporterPath
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $ImporterPath) { $ImporterPath = Join-Path $root '2-导入_InDesign\import_word_article_to_indesign.jsx' }
$directory = Join-Path ([IO.Path]::GetTempPath()) ('w2id-real-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
try {
    $jsonPath = Join-Path $directory 'article.json'
    & (Join-Path $root '1-提取_Word转JSON\docx_to_id_json.ps1') -DocxPath $DocxPath -OutputPath $jsonPath
    $data = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($PythonPath) {
        $pythonJson = Join-Path $directory 'python.json'
        & $PythonPath (Join-Path $root '1-提取_Word转JSON\docx_to_id_json.py') $DocxPath -o $pythonJson
        if ($LASTEXITCODE -ne 0) { throw 'Python conversion failed' }
        $other = Get-Content -LiteralPath $pythonJson -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($data.blocks.Count -ne $other.blocks.Count) { throw 'Converter block counts differ' }
        for ($i=0; $i -lt $data.blocks.Count; $i++) {
            $a=$data.blocks[$i]; $b=$other.blocks[$i]
            if ($a.text -cne $b.text -or $a.role -ne $b.role -or $a.runs.Count -ne $b.runs.Count) { throw "Converter mismatch block $i" }
            for ($j=0; $j -lt $a.runs.Count; $j++) {
                foreach ($property in 'start','end','position','italic','bold') {
                    if ($a.runs[$j].$property -cne $b.runs[$j].$property) { throw "Converter mismatch block $i run $j $property" }
                }
            }
        }
        Write-Host 'PASS PowerShell/Python blocks and UTF-16 runs match'
    }
    $source = [IO.File]::ReadAllText($ImporterPath, [Text.Encoding]::UTF8)
    $source = [regex]::Replace($source, 'File\.openDialog\([^;]*\);', ('File("'+$jsonPath.Replace('\','/')+'");'), 1)
    $script = @"
var alert=function(){}; var testDocument=app.activeDocument,testFrame=null,testResult="";
try {
    if (!/qa|副本|copy/i.test(testDocument.name)) throw new Error("Open a QA document copy first");
    testFrame=testDocument.textFrames.add({geometricBounds:[20,20,120,180]});app.select(testFrame);
    $source
    var f=File("$($jsonPath.Replace('\','/'))");f.encoding="UTF-8";f.open("r");var expected=eval("("+f.read()+")");f.close();
    var story=testFrame.parentStory;
    var substitutions={"｡":"。","＝":"=","¹":"1","²":"2","³":"3","⁰":"0","ⁱ":"i","⁴":"4","⁵":"5","⁶":"6","⁷":"7","⁸":"8","⁹":"9","⁺":"+","⁻":"-","⁼":"=","⁽":"(","⁾":")","ⁿ":"n","₀":"0","₁":"1","₂":"2","₃":"3","₄":"4","₅":"5","₆":"6","₇":"7","₈":"8","₉":"9","₊":"+","₋":"-","₌":"=","₍":"(","₎":")","ₐ":"a","ₑ":"e","ₒ":"o","ₓ":"x","ₕ":"h","ₖ":"k","ₗ":"l","ₘ":"m","ₙ":"n","ₚ":"p","ₛ":"s","ₜ":"t"};
    function comparable(t){var value="";for(var i=0;i<t.length;i++)value+=substitutions[t.charAt(i)]||t.charAt(i);return value.replace(/\s/g,"");}
    if(story.paragraphs.length!==expected.blocks.length) throw new Error("Paragraph count mismatch "+story.paragraphs.length+" vs "+expected.blocks.length);
    for(var i=0;i<expected.blocks.length;i++) {
        var actual=String(story.paragraphs[i].contents), original=String(expected.blocks[i].text);
        if(comparable(actual)!==comparable(original)) throw new Error("Text mismatch block "+i+": "+actual);
        if(expected.blocks[i].role==="table_gap" && actual!=="   \r") throw new Error("Table location missing block "+i);
    }
    var content=String(story.contents), prefix="给定输入特征图", at=content.indexOf(prefix);
    if(at>=0){var base=at+prefix.length;var offsets=[0,2,3,5,7];for(var k=0;k<offsets.length;k++){var c=story.characters[base+offsets[k]];if(c.fontStyle!=="Italic" || c.appliedFont.status!==FontStatus.INSTALLED)throw new Error("Italic missing "+c.contents);if(k>=2 && c.position!==Position.SUPERSCRIPT)throw new Error("Superscript missing "+c.contents);}}
    testResult="PASS real article "+expected.blocks.length+" blocks, full text and table locations";
}catch(e){testResult="ERROR|"+e+"|line="+e.line;}finally{if(testFrame && testFrame.isValid)testFrame.remove();}testResult;
"@
    $app = New-Object -ComObject 'InDesign.Application.2020'
    $result = $app.DoScript($script, 1246973031)
    if ($result -like 'ERROR|*') { throw $result }
    Write-Host $result
} finally {
    $resolved = [IO.Path]::GetFullPath($directory)
    if (-not $resolved.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected regression directory' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
