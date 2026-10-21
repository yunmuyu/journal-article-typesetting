param([Parameter(Mandatory=$true)][string]$ConfigPath,[Parameter(Mandatory=$true)][string]$ReportPath)
$ErrorActionPreference='Stop'
$config=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8|ConvertFrom-Json
if($config.articlePageRange){throw 'Use a standalone QA article fixture'}
$module=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../2-导入_InDesign/journal_layout_rules.jsxinc'))
$cfg=$config|ConvertTo-Json -Depth 20 -Compress
$fixture=Join-Path (Split-Path $ReportPath) ('table-tokens-'+[guid]::NewGuid().ToString('N')+'_QA.indd')
$fixtureJs=($fixture.Replace('\','/')|ConvertTo-Json -Compress)
$script=$module+@"
try {
 var c=$cfg,original=app.open(File(c.documentPath)),file=File($fixtureJs),report=[];original.saveACopy(file);
 function style(d,name){var a=d.allParagraphStyles;for(var i=0;i<a.length;i++)if(a[i].name===name)return a[i];throw Error('STYLE_MISSING '+name);}
 function test(name,mutate,code){var d=app.open(file);try{JournalLayout.bind(d,c);mutate(d);d.recompose();var result=JournalLayout.audit(d,c),found=false;for(var i=0;i<result.errors.length;i++)if(result.errors[i].code===code)found=true;if(!found)throw Error('MISSED '+name+' '+code);report.push('PASS '+name+' -> '+code);}finally{d.close(SaveOptions.NO);}}
 var d=app.open(file);JournalLayout.bind(d,c);var baseline=JournalLayout.audit(d,c);if(baseline.errors.length)throw Error('BASELINE '+baseline.errors[0].code);d.close(SaveOptions.NO);report.push('PASS clean article');
 test('fund last line',function(d){for(var i=0;i<d.stories.length;i++)if(d.stories[i].extractLabel('journal-role')==='footer')d.stories[i].paragraphs[1].justification=Justification.FULLY_JUSTIFIED;},'FUND_JUSTIFICATION');
 test('italic subscript becomes superscript',function(d){d.stories.itemByID(c.bindings[3].id).tables[0].cells[0].texts[0].characters[1].position=Position.SUPERSCRIPT;},'TABLE_SOURCE_FORMAT');
 test('italic subscript becomes upright',function(d){d.stories.itemByID(c.bindings[3].id).tables[0].cells[0].texts[0].characters[1].fontStyle='Regular';},'TABLE_SOURCE_FORMAT');
 test('citation splits',function(d){var p=d.stories.itemByID(c.bindings[3].id).paragraphs[4];p.noBreak=false;p.tracking=0;},'TOKEN_LINE_BREAK');
 test('local table and text bottom',function(d){var f=d.stories.itemByID(c.bindings[3].id).textContainers[c.localBottomPairs[0].frames[1]],b=f.geometricBounds;f.geometricBounds=[b[0]+1,b[1],b[2]+1,b[3]];},'LOCAL_BOTTOM');
 test('unequal figure whitespace',function(d){var items=d.allPageItems;for(var i=0;i<items.length;i++)if(items[i].label==='source-figure-'+c.balancedFigureGaps[0].number){var f=items[i].parent.parentStory.textContainers[0],b=f.geometricBounds;f.geometricBounds=[b[0]+1,b[1],b[2]+1,b[3]];break;}},'FIGURE_WHITESPACE');
 var d=app.open(file);try{JournalLayout.bind(d,c);var f=d.pages[-1].textFrames.add({geometricBounds:[210,17.5,245,62.5]});f.parentStory.insertLabel('journal-role','equation-probe');f.contents='x … y ≤ z ≥ t';f.paragraphs[0].applyParagraphStyle(style(d,'公式'),true);JournalLayout.applyTypography(d,c);if(String(f.contents).indexOf('…')>=0||String(f.contents).indexOf('⋯')<0)throw Error('ELLIPSIS_REPAIR');for(var ci=0;ci<f.characters.length;ci++){var ch=f.characters[ci],fam=String(ch.appliedFont.name).split(String.fromCharCode(9))[0];if(ch.contents==='⋯'&&fam!=='Cambria Math')throw Error('ELLIPSIS_FONT');if((ch.contents==='≤'||ch.contents==='≥')&&fam!=='宋体')throw Error('COMPARISON_FONT');}app.jpegExportPreferences.exportResolution=150;app.jpegExportPreferences.exportingSpread=false;app.jpegExportPreferences.jpegExportRange=ExportRangeOrAllPages.EXPORT_RANGE;app.jpegExportPreferences.pageString=d.pages[-1].name;d.exportFile(ExportFormat.JPG,File(file.fsName+'.jpg'),false);report.push('PASS centered formula ellipsis and both comparisons');f.remove();var unit=d.pages[-1].textFrames.add({geometricBounds:[210,17.5,245,44.5]});unit.parentStory.insertLabel('journal-role','quantity-probe');unit.contents='测试文字10 562 kg与5×10-3 s';unit.paragraphs[0].applyParagraphStyle(style(d,'正文_wrd_1'),true);unit.texts[0].pointSize=10.5;unit.texts[0].leading=15;unit.texts[0].noBreak=false;JournalLayout.protectLineTokens(d);var p=unit.paragraphs[0],text=String(p.contents),samples=['10 562 kg','5×10-3 s'];for(var si=0;si<samples.length;si++){var start=text.indexOf(samples[si]);if(start<0)throw Error('TOKEN_SAMPLE');for(var ci=start;ci<start+samples[si].length;ci++)if(!p.characters[ci].noBreak)throw Error('QUANTITY_NOT_PROTECTED '+samples[si]);}report.push('PASS grouped number, unit and scientific notation protection');}finally{d.close(SaveOptions.NO);}
 report.join('\n');
}catch(e){'ERROR '+e+' LINE '+e.line;}
"@
$app=New-Object -ComObject InDesign.Application.2020
$result=[string]$app.DoScript($script,1246973031)
[IO.File]::WriteAllText($ReportPath,$result,[Text.UTF8Encoding]::new($false))
$result
if($result -match 'ERROR|MISSED'){throw 'Regression failed'}
