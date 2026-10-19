param([string]$ImporterPath)
$ErrorActionPreference = 'Stop'
if (-not $ImporterPath) { $ImporterPath = Join-Path (Split-Path -Parent $PSScriptRoot) '2-导入_InDesign\import_word_article_to_indesign.jsx' }
$source = [IO.File]::ReadAllText($ImporterPath,[Text.Encoding]::UTF8)
$fixture = (Join-Path $PSScriptRoot 'chinese_italic_input.json').Replace('\','/')
$source = [regex]::Replace($source,'File\.openDialog\([^;]*\);',('File("' + $fixture + '");'),1)
$script = @"
var alert=function(){};
if (!/qa|copy|副本/i.test(app.activeDocument.name)) throw new Error("Open a template copy before testing.");
var doc=app.activeDocument, frame=null, result="";
try {
    // Given: the real template and Word's italic flag on the Chinese enumeration comma.
    frame=doc.textFrames.add();frame.geometricBounds=[-50,-50,-20,-10];app.select(frame);
    // When: import through the actual source.
    $source
    // Then: Chinese punctuation uses the Chinese font, Latin variables remain italic/subscript.
    var paragraphs=frame.parentStory.paragraphs, chars=paragraphs[0].characters;
    result=String(paragraphs[0].contents)+"|"+String(chars[2].appliedFont.fontFamily)+"|"+String(chars[2].appliedFont.status)+"|"+
        String(chars[0].appliedFont.fontFamily)+"|"+String(chars[0].fontStyle)+"|"+String(chars[1].position)+"|"+
        String(chars[3].appliedFont.fontFamily)+"|"+String(chars[3].fontStyle)+"|"+String(chars[4].position);
    var mixed=paragraphs[1].characters, bold=paragraphs[2].characters, chineseBold=paragraphs[3].characters;
    if (String(mixed[0].appliedFont.fontFamily).indexOf("Times")!==-1 || mixed[0].skew!==12 || mixed[1].skew!==12 || mixed[2].skew!==0 || mixed[4].skew!==0) throw new Error("Mixed Chinese italic text/punctuation font or slant incorrect.");
    if (String(mixed[3].appliedFont.fontFamily)!=="Times New Roman" || String(mixed[3].fontStyle)!=="Italic") throw new Error("Mixed Latin italic lost.");
    if (String(bold[1].appliedFont.fontFamily).indexOf("Times")!==-1 || String(bold[0].fontStyle)!=="Bold Italic" || String(bold[2].fontStyle)!=="Bold Italic") throw new Error("BoldItalic punctuation/Latin split incorrect.");
    if (String(chineseBold[0].appliedFont.fontFamily).indexOf("Times")!==-1 || chineseBold[0].appliedFont.status!==FontStatus.INSTALLED || chineseBold[0].skew!==12 || chineseBold[0].pointSize!==10.5 || String(chineseBold[3].fontStyle)!=="Bold Italic") throw new Error("Chinese BoldItalic font/size/slant incorrect.");
} catch(e) { result="ERROR|"+String(e)+"|line="+e.line; }
finally { if (frame && frame.isValid) frame.remove(); }
result;
"@
$app = New-Object -ComObject 'InDesign.Application.2020'
$result = $app.DoScript($script,1246973031)
if ($result -like 'ERROR|*') { throw $result }
$parts = @($result -split '\|')
if ($parts[0].TrimEnd("`r") -cne 'Lf、Lb。') { throw 'Imported punctuation/text changed.' }
if ($parts[1] -notmatch '宋|Song') { throw "Chinese italic comma received $($parts[1]); expected the template Chinese font." }
if ($parts[2] -ne 'INSTALLED' -and $parts[2] -ne '1718831470') { throw 'Chinese punctuation font unavailable.' }
if ($parts[3] -ne 'Times New Roman' -or $parts[4] -ne 'Italic' -or $parts[6] -ne 'Times New Roman' -or $parts[7] -ne 'Italic') { throw 'Latin variables lost Times New Roman Italic.' }
if ($parts[5] -ne 'SUBSCRIPT' -and $parts[5] -ne '1935831907') { throw 'f lost subscript.' }
if ($parts[8] -ne 'SUBSCRIPT' -and $parts[8] -ne '1935831907') { throw 'b lost subscript.' }
Write-Output 'PASS Chinese italic punctuation stays in template Chinese font; Latin italic and subscripts preserved.'
