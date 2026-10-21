param(
    [Parameter(Mandatory=$true)][string[]]$ManifestPaths,
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '../2-导入_InDesign/JournalInDesignScript.psm1') -Force
$directory=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $directory -Force|Out-Null
$module=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../2-导入_InDesign/journal_article_assembly.jsxinc'))
$seam='return {growBodyPages:'
if(-not $module.Contains($seam)){throw 'FORMULA_TEST_ASSEMBLY_EXPORT'}
$module=$module.Replace($seam,'return {testDisplayFormula:formula,growBodyPages:')
$app=New-Object -ComObject InDesign.Application.2020
$reports=@()
foreach($manifestPath in $ManifestPaths){
    $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
    if($manifest.mode -ne 'native-idms' -or @($manifest.entries).Count -ne $manifest.formula_count){throw 'FORMULA_TEST_MANIFEST'}
    foreach($entry in $manifest.entries){if((Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash -ine $entry.sha256){throw 'FORMULA_TEST_IDMS_CHANGED'}}
    $name=Split-Path (Split-Path $manifest.sourceWord -Parent) -Leaf
    $output=Join-Path $directory ($name+'_正文公式专项_QA.indd')
    if(Test-Path -LiteralPath $output){throw 'FORMULA_TEST_OUTPUT_EXISTS'}
    $spec=@{output=$output;manifest=$manifest}|ConvertTo-Json -Depth 35 -Compress
    $code=$module+@"
(function(s){try{
 var m=s.manifest,d=app.documents.add().getElements()[0];d.insertLabel('journal-formula-test-owned','true');d.documentPreferences.facingPages=false;d.documentPreferences.pagesPerDocument=1;
 d.documentPreferences.pageWidth='210mm';d.documentPreferences.pageHeight='297mm';
 d.viewPreferences.horizontalMeasurementUnits=MeasurementUnits.MILLIMETERS;d.viewPreferences.verticalMeasurementUnits=MeasurementUnits.MILLIMETERS;
 var st=d.paragraphStyles.add({name:'公式',pointSize:10.5,leading:15,appliedFont:app.fonts.itemByName('宋体\t常规')});
 st.tabStops.add({position:89,alignment:TabStopAlignment.CENTER_ALIGN});st.tabStops.add({position:178,alignment:TabStopAlignment.RIGHT_ALIGN});
 var f=d.pages[0].textFrames.add({geometricBounds:[20,16,275,194]}).getElements()[0],texts=[];
 for(var i=0;i<m.entries.length;i++){var e=m.entries[i];texts.push(e.inline?'x'+e.marker+'i':e.marker+(e.displayNumber===null?'':' ('+e.displayNumber+')'));}
 f.contents=texts.join('\r')+'\r';f.parentStory.texts[0].properties={appliedFont:app.fonts.itemByName('Times New Roman\tRegular'),pointSize:10.5,leading:15};
 for(i=0;i<m.entries.length;i++){
  e=m.entries[i];var currentFormulaNumber=e.number,p=f.parentStory.paragraphs[i].getElements()[0];
  if(e.inline){p.characters[0].fontStyle='Italic';p.characters[-2].position=Position.SUBSCRIPT;var styleId=p.appliedParagraphStyle.id,just=p.justification;
   JournalArticleAssembly.inlineFormulas(d,p,JournalArticleAssembly.formulaMarkers(p.contents),{formulas:m},null);
   if(p.appliedParagraphStyle.id!==styleId||p.justification!==just)throw Error('INLINE_PARAGRAPH_CHANGED');
  }else JournalArticleAssembly.testDisplayFormula(d,p,e.number,{formulas:m},null,texts[i]);
  p.spaceAfter='12pt';
 }
 d.recompose();var frame=f;while(f.parentStory.overflows){if(d.pages.length>m.entries.length)throw Error('TEST_PAGINATION_NO_PROGRESS');var page=d.pages.add(),next=page.textFrames.add({geometricBounds:[20,16,275,194]}).getElements()[0];frame.nextTextFrame=next;frame=next;d.recompose();}
 function verify(doc){
  doc.recompose();if(doc.allGraphics.length||doc.links.length||doc.stories.length!==1||doc.stories[0].overflows)throw Error('LINK_OR_OVERSET');
  var count=0,items=doc.allPageItems;
  for(var k=0;k<items.length;k++)if(/^source-formula-/.test(items[k].label)){
   var g=items[k],n=Number(g.label.replace('source-formula-','')),entry=JournalArticleAssembly.idmsEntry(m,n),b=g.geometricBounds;
   if(g.constructor.name!=='Group'||g.allGraphics.length||g.parent.constructor.name!=='Character'||g.extractLabel('formula-native-paste')!=='true'||Number(g.extractLabel('formula-base-point-size'))!==10.5)throw Error('NOT_NATIVE_ANCHORED');
   if(Math.abs(g.absoluteHorizontalScale-100)>.001||Math.abs(g.absoluteVerticalScale-100)>.001||Math.abs(b[3]-b[1]-entry.widthMm)>.02||Math.abs(b[2]-b[0]-entry.heightMm)>.02)throw Error('NATIVE_DIMENSIONS');count++;
  }
  if(count!==m.entries.length)throw Error('FORMULA_COUNT');
  for(k=0;k<m.entries.length;k++){
   var en=m.entries[k],para=doc.stories[0].paragraphs[k],text=String(para.contents);
   if(/⟦EQ-/.test(text))throw Error('MARKER_REMAINS');
   if(en.inline){if(text.replace(/[\s\uFFFC]/g,'')!=='xi'||String(para.characters[0].fontStyle)!=='Italic'||para.characters[-2].position!==Position.SUBSCRIPT)throw Error('INLINE_NEIGHBORS');}
   else if(en.displayNumber===null){if(text.replace(/[\s\uFFFC]/g,'')!==''||para.justification!==Justification.CENTER_ALIGN)throw Error('UNNUMBERED_FORMULA');}
   else if(text.indexOf('（'+en.displayNumber+'）')<0)throw Error('DISPLAY_NUMBER');
  }
 }
 verify(d);d.save(File(s.output));d.close(SaveOptions.YES);d=app.open(File(s.output));verify(d);
 d.insertLabel('journal-formula-test','saved-reopened-verified');d.save();d.close(SaveOptions.YES);
 return 'PASS';
}catch(e){return 'ERROR formula='+currentFormulaNumber+' '+e+' LINE '+e.line;}finally{if(d&&d.isValid&&d.extractLabel('journal-formula-test-owned')==='true')d.close(SaveOptions.NO);}})($spec);
"@
    $answer=[string](Invoke-JournalInDesignScript -Application $app -Code $code)
    if($answer -ne 'PASS'){throw $answer}
    $reports+=@([ordered]@{source=$manifest.sourceWord;sourceSHA256=$manifest.sourceWordSHA256;manifest=(Get-Item -LiteralPath $manifestPath).FullName;output=$output;outputSHA256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash;passed=$true;formulaCount=$manifest.formula_count;inlineCount=@($manifest.entries|Where-Object inline).Count;unnumberedCount=@($manifest.entries|Where-Object {-not $_.inline -and $null -eq $_.displayNumber}).Count;savedAndReopened=$true;linkedGraphics=0;nativeSizeAndScaleVerified=$true;neighborItalicAndSubscriptVerified=$true})
}
$reportPath=Join-Path $directory '正文公式专项结果.json'
[IO.File]::WriteAllText($reportPath,($reports|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
$reports|ConvertTo-Json -Depth 15
