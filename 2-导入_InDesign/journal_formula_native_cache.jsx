(function(job){
 function targetDocument(){
  var d=app.documents.itemByName(job.documentName).getElements()[0];
  if(!d.isValid)throw Error('FORMULA_DOCUMENT_NOT_OPEN '+job.documentName);
  return d;
 }
 function anchorFor(d){
  var story=null,index=-1,count=0;
  if(job.markerText){
   for(var si=0;si<d.stories.length;si++){
    var at=String(d.stories[si].contents).indexOf(job.markerText);
    if(at>=0){story=d.stories[si].getElements()[0];index=at;count++;}
   }
   if(count!==1)throw Error('FORMULA_MARKER_COUNT '+count);
   story.characters.itemByRange(index,index+job.markerText.length-1).remove();
   return {story:story,index:index};
  }
  var old=null,items=d.allPageItems;
  for(var i=0;i<items.length;i++)if(items[i].label===job.placeholderLabel){old=items[i];count++;}
  if(count!==1)throw Error('FORMULA_PLACEHOLDER_COUNT '+count);
  var parent=old.parent;if(parent.constructor.name!=='Character')throw Error('FORMULA_PLACEHOLDER_NOT_ANCHORED');
  story=parent.parentStory;index=parent.index;old.remove();
  return {story:story,index:index};
 }
 function nativeGroup(item){
  if(!item||item.allGraphics.length)throw Error('FORMULA_NOT_NATIVE_GROUP');
  item=item.getElements()[0];
  if(item.constructor.name!=='Group'){
   if(!/^(Polygon|Rectangle|Oval|GraphicLine)$/.test(item.constructor.name))throw Error('FORMULA_NOT_NATIVE_VECTOR');
   var owner=item.parent, bounds=owner.rectangles.add({geometricBounds:item.geometricBounds,strokeWeight:0,fillColor:d.swatches.itemByName('None'),strokeColor:d.swatches.itemByName('None')}).getElements()[0];
   bounds.nonprinting=true;bounds.label='formula-native-bounds';
   item=owner.groups.add([item,bounds]).getElements()[0];
  }
  return item;
 }
 function label(group){
  group.label='source-formula-'+job.number;
  group.insertLabel('formula-native-paste','true');
  group.insertLabel('formula-base-point-size','10.5');
  group.insertLabel('formula-cache-key',job.cacheKey);
  group.insertLabel('formula-source-sha256',job.sourceSha256);
  group.insertLabel('formula-rule-version',job.ruleVersion);
  group.insertLabel('formula-source-ai',job.aiPath);
  group.insertLabel('journal-component-key',job.cacheKey);
  group.insertLabel('journal-component-hash',job.sourceSha256);
  group.insertLabel('journal-component-kind','formula');
 }
 var d=targetDocument(),anchor=anchorFor(d),group=null,oldClipboard=app.clipboardPreferences.preferPDFWhenPasting;
 try{
  if(!d.windows.length)d.windows.add();app.activeWindow=d.layoutWindows[0];if(app.activeDocument.id!==d.id)throw Error('FORMULA_TARGET_NOT_ACTIVE');
  if(job.action==='paste-and-cache'){
   if(File(job.idmsPath).exists)throw Error('FORMULA_IDMS_EXISTS');
   app.clipboardPreferences.preferPDFWhenPasting=false;app.select(NothingEnum.NOTHING);app.paste();
   if(app.selection.length!==1)throw Error('FORMULA_PASTE_SELECTION '+app.selection.length);
   group=nativeGroup(app.selection[0]);
   label(group);group.exportFile(ExportFormat.INDESIGN_SNIPPET,File(job.idmsPath));
   group.anchoredObjectSettings.insertAnchoredObject(anchor.story.insertionPoints[anchor.index],AnchorPosition.INLINE_POSITION);
  }else if(job.action==='reuse-idms'){
   if(!File(job.idmsPath).exists)throw Error('FORMULA_IDMS_MISSING');
   var placed=d.pages[0].place(File(job.idmsPath));
   if(!placed||placed.length!==1)throw Error('FORMULA_IDMS_PLACE_COUNT');
   group=nativeGroup(placed[0]);group.anchoredObjectSettings.insertAnchoredObject(anchor.story.insertionPoints[anchor.index],AnchorPosition.INLINE_POSITION);label(group);
  }else throw Error('FORMULA_CACHE_ACTION '+job.action);
  if(group.absoluteHorizontalScale!==100||group.absoluteVerticalScale!==100)throw Error('FORMULA_SCALE');
  d.recompose();var b=group.geometricBounds;
  return [job.action,job.number,b[3]-b[1],b[2]-b[0],group.allGraphics.length].join('\t');
 }finally{app.clipboardPreferences.preferPDFWhenPasting=oldClipboard;}
})(JournalFormulaNativeCacheJob);
