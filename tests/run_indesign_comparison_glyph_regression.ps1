param()
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$importer=[IO.File]::ReadAllText((Join-Path $project '2-导入_InDesign\import_word_article_to_indesign.jsx'))
$fixture=(Join-Path $PSScriptRoot 'comparison_glyph_input.json').Replace('\','/')
$importer=[regex]::Replace($importer,'File\.openDialog\([^;]*\);',('File("'+$fixture+'");'),1)
$app=New-Object -ComObject InDesign.Application.2020
foreach($control in @($true,$false)){
 $source=$importer
 if($control){$source=$source.Replace('c.appliedFont=songFont;c.fontStyle="Regular";','c.appliedFont=app.fonts.itemByName("黑体");c.fontStyle="Regular";')}
 $script=@"
var alert=function(){};
(function(){var d=app.activeDocument,f=d.textFrames.add();try{f.geometricBounds=[-50,-50,-20,-20];app.select(f);
$source
var s=f.parentStory,o=[];for(var i=0;i<s.characters.length;i++){var c=s.characters[i];if(c.contents==='≤'||c.contents==='≥')o.push(c.contents+'|'+c.appliedFont.fontFamily+'|'+c.pointSize);}return o.join(';');}finally{f.remove();}})();
"@
 $result=[string]$app.DoScript($script,1246973031)
 $wanted=if($control){'≤|黑体|10.5;≥|黑体|10.5'}else{'≤|宋体|10.5;≥|宋体|10.5'}
 if($result -cne $wanted){throw "Comparison regression failed control=${control}: $result"}
 Write-Output $(if($control){'CONTROL old Black comparison-font behavior reproduced'}else{'PASS both ≤ and ≥ use Song at 10.5 pt'})
}