/* One formula per Illustrator DoJavaScript call: a new event clears stale WMF document proxies. */
(function(job){
 if(!job||!job.number||!job.inputDirectory||!job.outputDirectory)throw Error('FORMULA_JOB_REQUIRED');
 var stage='open',n=job.number,out=Folder(job.outputDirectory);if(!out.exists&&!out.create())throw Error('OUTPUT_DIRECTORY');
 var song=app.textFonts.getByName('SimSun');
 var sourceFile=File(job.inputDirectory+'/formula-'+n+'.wmf');
 for(var pi=0;pi<app.documents.length;pi++){
  var existingPath='';try{existingPath=String(app.documents[pi].fullName.fsName);}catch(pathError){}
  if(existingPath.toLowerCase()===String(sourceFile.fsName).toLowerCase())throw Error('FORMULA_SOURCE_ALREADY_OPEN');
 }
 var d=app.open(sourceFile);
 try{
  var base=0,moved=0,changed=0;
  // The formula's base point size is the dominant full-size character size, not the
  // largest glyph: a single oversized operator must not rescale the whole formula.
  // Sub/superscripts fall outside the 9-14pt band and are ignored.
  var sizes=[],counts=[],baseKeys=[];
  for(var i=0;i<d.textFrames.length;i++)for(var j=0;j<d.textFrames[i].characters.length;j++){
   var size=d.textFrames[i].characters[j].characterAttributes.size,slot=-1;
   for(var c=0;c<sizes.length;c++)if(Math.abs(sizes[c]-size)<.001){slot=c;break;}
   if(slot<0){sizes.push(size);counts.push(0);slot=sizes.length-1;}
   counts[slot]++;
  }
  var baseCount=0;
  for(var c=0;c<sizes.length;c++){
   if(sizes[c]<9||sizes[c]>14)continue;
   if(counts[c]>baseCount||(counts[c]===baseCount&&sizes[c]>base)){base=sizes[c];baseCount=counts[c];}
  }
  if(base===0)throw Error('SOURCE_FORMULA_SIZE_UNRESOLVED sizes='+sizes.join(','));
  for(var i=0;i<d.textFrames.length;i++)for(var j=0;j<d.textFrames[i].characters.length;j++)if(Math.abs(d.textFrames[i].characters[j].characterAttributes.size-base)<.001)baseKeys.push(i+':'+j);
  if(!baseKeys.length)throw Error('SOURCE_FORMULA_BASE_UNCOUNTED '+base);
  for(var i=0;i<d.textFrames.length;i++){var t=d.textFrames[i];if(t.contents==='，')for(var k=0;k<d.textFrames.length;k++){var other=d.textFrames[k];if(other.contents==='时'&&Math.abs(t.left-other.left)<.01&&Math.abs(t.top-other.top)<.01){t.left+=base;moved++;break;}}}
  var tops=[],all=d.groupItems.add();for(var i=0;i<d.pageItems.length;i++){var x=d.pageItems[i];if(x!==all&&(x.parent.typename==='Layer'||x.parent.typename==='Document'))tops.push(x);}for(var i=tops.length-1;i>=0;i--)tops[i].move(all,ElementPlacement.PLACEATBEGINNING);
  var scale=10.5/base*100;all.resize(scale,scale,true,true,true,true,scale,Transformation.TOPLEFT);
  // Output guarantee: every character that carried the base size must now measure
  // exactly 10.5pt. This is checked per character, so a wrong base cannot hide
  // behind whichever glyph happens to be largest.
  var frames=[],comparisons=[],glyphs=[],worst=0;
  for(var b=0;b<baseKeys.length;b++){
   var parts=baseKeys[b].split(':'),measured=d.textFrames[Number(parts[0])].characters[Number(parts[1])].characterAttributes.size,offset=Math.abs(measured-10.5);
   if(offset>worst)worst=offset;
  }
  if(worst>.02)throw Error('OUTPUT_FORMULA_SIZE '+worst);
  for(var i=0;i<d.textFrames.length;i++){var t=d.textFrames[i];frames.push(t);for(var j=0;j<t.characters.length;j++){var a=t.characters[j].characterAttributes;if(t.characters[j].contents==='≤'||t.characters[j].contents==='≥'){comparisons.push({frameIndex:i,charIndex:j,charCount:t.characters.length,character:t.characters[j].contents,anchor:t.anchor,size:a.size});}}}
  for(var i=frames.length-1;i>=0;i--){var source=frames[i],outlined=source.createOutline(),letters=[];for(var j=0;j<outlined.pageItems.length;j++){var item=outlined.pageItems[j];if(item.parent!==outlined)continue;glyphs.push(item);letters.push(item);}letters.sort(function(a,b){return a.left-b.left;});for(var j=0;j<comparisons.length;j++)if(comparisons[j].frameIndex===i){if(letters.length!==comparisons[j].charCount)throw Error('COMPARISON_GLYPH_MAPPING');comparisons[j].oldGlyph=letters[comparisons[j].charIndex];}}
  comparisons.sort(function(a,b){return b.oldGlyph.left-a.oldGlyph.left;});
  var comparisonAudit=['symbol\tscaledSourcePt\toutputPt'];
  for(var i=0;i<comparisons.length;i++){
   var c=comparisons[i],old=c.oldGlyph,b=old.geometricBounds;
   stage='create-song-point';var text=d.textFrames.pointText([b[0],c.anchor[1]]);text.contents=c.character;text.textRange.characterAttributes.textFont=song;text.textRange.characterAttributes.size=c.size;
   if(text.textRange.characterAttributes.textFont.name!==song.name||Math.abs(text.textRange.characterAttributes.size-c.size)>.02)throw Error('COMPARISON_FONT_SIZE '+text.textRange.characterAttributes.size+' '+text.textRange.characterAttributes.textFont.name);
   comparisonAudit.push(text.contents+'\t'+c.size+'\t'+text.textRange.characterAttributes.size);
   stage='outline-song';var replacement=text.createOutline();replacement.left=b[0];replacement.top=(b[1]+b[3]+replacement.height)/2;var delta=Math.max(0,replacement.width-(b[2]-b[0]));
   stage='move-following-glyphs';for(var j=0;j<glyphs.length;j++)if(glyphs[j]!==old&&glyphs[j].left>b[0]+.01)glyphs[j].translate(delta,0);
   for(var gi=glyphs.length-1;gi>=0;gi--)if(glyphs[gi]===old)glyphs.splice(gi,1);old.remove();glyphs.push(replacement);changed++;
  }
  var audit=File(out.fsName+'/comparison-font-audit.tsv');audit.encoding='UTF-8';audit.open('w');audit.write(comparisonAudit.join('\n'));audit.close();
  if(d.textFrames.length)throw Error('FORMULA_NOT_OUTLINED');
  var b=d.visibleBounds;d.artboards[0].artboardRect=[b[0]-.2,b[1]+.2,b[2]+.2,b[3]-.2];
  d.saveAs(File(out.fsName+'/formula-'+n+'-10p5-simsun.ai'),new IllustratorSaveOptions());
  var optionalPdf=job.exportPdf!==false;
  if(optionalPdf){var pdf=new PDFSaveOptions();pdf.preserveEditability=false;pdf.compatibility=PDFCompatibility.ACROBAT5;d.saveAs(File(out.fsName+'/formula-'+n+'-10p5-simsun.pdf'),pdf);}
  var optionalPng=job.exportPng!==false;
  if(optionalPng){var png=new ExportOptionsPNG24();png.artBoardClipping=true;png.horizontalScale=400;png.verticalScale=400;png.transparency=false;d.exportFile(File(out.fsName+'/formula-'+n+'-10p5-simsun.png'),ExportType.PNG24,png);}
  return [n,base,10.5-worst,changed,moved,b[2]-b[0]+.4,b[1]-b[3]+.4].join('\t');
 }catch(error){var log=File(out.fsName+'/repair-error.txt');log.open('w');log.write(stage+' '+error+' LINE '+error.line);log.close();throw error;}
 finally{
  // saveAs changes fullName, so ownership is tracked by the document reference this
  // call opened rather than by path. Pre-opened and unrelated documents are never
  // touched. A failure while closing must not mask the original error.
  try{if(d)d.close(SaveOptions.DONOTSAVECHANGES);}catch(closeError){}
 }
})(JournalFormulaJob);
