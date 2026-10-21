(function(j){
var d=app.documents.itemByID(j.documentId).getElements()[0];if(!d.isValid||d.fullName.fsName.toLowerCase()!==j.documentPath.toLowerCase())throw Error('TARGET_CHANGED');
var ruler=d.viewPreferences.rulerOrigin;d.viewPreferences.rulerOrigin=RulerOrigin.SPREAD_ORIGIN;var old=null,items=d.allPageItems,count=0;
for(var i=0;i<items.length;i++){var o=items[i];if(o.label==='source-formula-'+j.number&&(!j.articlePageRange||(o.parentPage&&o.parentPage.documentOffset>=j.articlePageRange[0]&&o.parentPage.documentOffset<=j.articlePageRange[1]))){old=o;count++;}}
if(count!==1||(old.allGraphics.length!==1&&old.constructor.name!=='Group'))throw Error('OLD_FORMULA_COUNT_OR_TYPE '+count);
var oldGraphics=old.allGraphics.length,metadata=[],keys=['formula-display','formula-number-fit','formula-center-mm','formula-printed-number'];for(var ki=0;ki<keys.length;ki++)metadata.push([keys[ki],old.extractLabel(keys[ki])]);var parent=old.parent,story=parent.parentStory,index=parent.index,p=parent.paragraphs[0],text=String(story.contents),bounds=old.geometricBounds.slice(0),oldBaseline=p.lines[0].baseline,shift=parent.baselineShift,leading=p.leading,anchorY=old.anchoredObjectSettings.anchorYoffset;
var pref=app.clipboardPreferences.preferPDFWhenPasting,g=null;
try{
if(!d.windows.length)d.windows.add();app.activeWindow=d.layoutWindows[0];if(app.activeDocument.id!==d.id)throw Error("PASTE_TARGET_CHANGED");app.clipboardPreferences.preferPDFWhenPasting=false;app.select(NothingEnum.NOTHING);app.paste();
if(app.selection.length!==1)throw Error('PASTE_COUNT');g=app.selection[0].getElements()[0];
if(g.constructor.name!=='Group'||g.allGraphics.length)throw Error('PASTE_NOT_NATIVE');
var nb=g.geometricBounds,ob=j.originalBounds||bounds,w=ob[3]-ob[1],h=ob[2]-ob[0],dx=(w-(nb[3]-nb[1]))/2,dy=(h-(nb[2]-nb[0]))/2;
if(dx<-.01||dy<-.01||dx>.2||dy>.2)throw Error('SOURCE_EXTENT_MISMATCH');
var pad=g.parent.rectangles.add().getElements()[0];pad.applyObjectStyle(d.objectStyles[0],true,true);pad.geometricBounds=[nb[0]-dy,nb[1]-dx,nb[2]+dy,nb[3]+dx];pad.fillColor=d.swatches.itemByName('None');pad.strokeColor=d.swatches.itemByName('None');pad.strokeWeight=0;
pad.label='formula-layout-padding';g=g.parent.groups.add([g,pad]);
g.anchoredObjectSettings.insertAnchoredObject(story.insertionPoints[index],AnchorPosition.INLINE_POSITION);
g.anchoredObjectSettings.anchorYoffset=anchorY;g.parent.baselineShift=shift;
g.label='source-formula-'+j.number;for(var mi=0;mi<metadata.length;mi++)if(metadata[mi][1])g.insertLabel(metadata[mi][0],metadata[mi][1]);g.insertLabel('formula-native-paste','true');g.insertLabel('formula-base-point-size','10.5');g.insertLabel('formula-source-ai',j.sourceAi);g.insertLabel('formula-source-sha256',j.sourceSha256);g.insertLabel('formula-rule-version','10.5-simsun-outline');g.insertLabel('formula-layout-padding','source-artboard-0.2pt');
old.remove();JournalLayout.formulaPadding(d,true);d.recompose();var actual=g.geometricBounds;if(Math.abs(actual[3]-actual[1]-w)>.01||Math.abs(actual[2]-actual[0]-h)>.01)throw Error('NATIVE_LAYOUT_EXTENT');
if(String(story.contents)!==text)throw Error('TEXT_CHANGED');
if(Math.abs(g.absoluteHorizontalScale-100)>.001||Math.abs(g.absoluteVerticalScale-100)>.001)throw Error('NATIVE_SCALE');
return JournalRegressionSnapshot.json({passed:true,documentId:d.id,number:j.number,id:g.id,type:g.constructor.name,graphics:g.allGraphics.length,oldGraphics:oldGraphics,oldBounds:bounds,newBounds:g.geometricBounds,oldBaseline:oldBaseline,newBaseline:g.parent.paragraphs[0].lines[0].baseline,leading:g.parent.paragraphs[0].leading,sourceSha256:j.sourceSha256});
}finally{app.clipboardPreferences.preferPDFWhenPasting=pref;d.viewPreferences.rulerOrigin=ruler;}
})(JournalFormulaReplaceJob);
