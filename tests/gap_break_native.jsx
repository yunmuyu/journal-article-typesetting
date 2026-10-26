(function(){
 var d=null,ui=app.scriptPreferences.userInteractionLevel,redraw=app.scriptPreferences.enableRedraw,existing=[],result={passed:false};
 function check(ok,message){if(!ok)throw Error(message);}
 try{
  for(var i=0;i<app.documents.length;i++)existing.push(app.documents[i].id);
  app.scriptPreferences.userInteractionLevel=UserInteractionLevels.NEVER_INTERACT;app.scriptPreferences.enableRedraw=false;
  d=app.documents.add(false);d.documentPreferences.properties={facingPages:false,pageWidth:'210mm',pageHeight:'297mm',pagesPerDocument:2};
  d.viewPreferences.properties={horizontalMeasurementUnits:MeasurementUnits.MILLIMETERS,verticalMeasurementUnits:MeasurementUnits.MILLIMETERS,rulerOrigin:RulerOrigin.PAGE_ORIGIN};d.zeroPoint=[0,0];
  var fs=[],font=app.fonts.itemByName('Times New Roman\tRegular');check(font.isValid,'FONT_MISSING');
  for(i=0;i<4;i++){var x=i%2?107:14.5;fs.push(d.pages[Math.floor(i/2)].textFrames.add({geometricBounds:[26,x,110,x+85.5]}));if(i%2)fs[i-1].nextTextFrame=fs[i];}
  var style=d.paragraphStyles.add({name:'正文',appliedFont:font,pointSize:10.5,leading:15,spaceBefore:0,spaceAfter:0,keepWithNext:0});
  var refStyle=d.paragraphStyles.add({name:'参考文献 内容',appliedFont:font,pointSize:9,leading:13,spaceBefore:0,spaceAfter:0});
  var a=fs[0].parentStory,b=fs[2].parentStory;a.insertLabel('journal-role','body');b.insertLabel('journal-role','body');
  a.contents='Introduction one.\rIntroduction two.\rReferences:\r[1] A reference should follow its heading.\r';a.paragraphs.everyItem().appliedParagraphStyle=style;
  var p=a.paragraphs[3];p.appliedParagraphStyle=refStyle;p.startParagraph=StartParagraph.NEXT_COLUMN;
  b.contents='Other article.\rKeep this paragraph in the next column.\r';b.paragraphs.everyItem().appliedParagraphStyle=style;b.paragraphs[1].startParagraph=StartParagraph.NEXT_COLUMN;
  d.recompose();var untouched=JournalLayoutMeasurement.flowSignature(b),text=String(a.contents),c={bindings:[{id:a.id,role:'body'}],articlePageRange:[0,0],gapSolver:{maxBoundaries:1}};
  var original=File(NativeGapEvidenceDirectory+'/自动换栏_source_QA.indd');d.save(original);
  var blocked=JournalGapLayout.solve(d,c);check(blocked.status==='blocked-large-gaps','MANUAL_BREAK_MUST_BLOCK');check(p.startParagraph===StartParagraph.NEXT_COLUMN,'MANUAL_BREAK_CHANGED');
  JournalGapLayout.registerAutomaticBreak(a,p);var adapter=JournalGapLayout.adapter(d,c),state=adapter.measure(),saved=adapter.snapshot(state),planned=JournalGapSolver.plan(state,0,c.gapSolver).candidates[0];
  check(planned.mode==='release-break','STRUCTURAL_CANDIDATE_MISSING');adapter.apply(planned);check(p.startParagraph===StartParagraph.ANYWHERE,'TRIAL_NOT_RELEASED');adapter.restore(saved);check(p.startParagraph===StartParagraph.NEXT_COLUMN,'ROLLBACK_BREAK_FAILED');
  var solved=JournalGapLayout.solve(d,c);check(solved.status==='gap-check-passed','AUTO_BREAK_NOT_SOLVED');check(solved.decisions[0].selected.mode==='release-break','WRONG_DECISION');check(p.startParagraph===StartParagraph.ANYWHERE,'AUTO_BREAK_REMAINED');
  check(p.insertionPoints[0].parentTextFrames[0].id===a.paragraphs[2].insertionPoints[0].parentTextFrames[0].id,'REFERENCE_HEADING_SPLIT');
  check(String(a.contents)===text,'SOURCE_TEXT_CHANGED');check(JournalLayoutMeasurement.flowSignature(b)===untouched,'OTHER_ARTICLE_CHANGED');
  p.startParagraph=StartParagraph.NEXT_COLUMN;d.recompose();check(!JournalGapLayout.breakControl(a,p,c).releasable,'LATER_MANUAL_BREAK_MISCLASSIFIED');p.startParagraph=StartParagraph.ANYWHERE;d.recompose();
  fs[0].geometricBounds=[26,14.5,110,92];d.recompose();check(p.startParagraph===StartParagraph.ANYWHERE,'RESIZE_REINTRODUCED_BREAK');
  var before=String(a.contents);a.contents='';for(i=0;i<36;i++)a.insertionPoints[-1].contents='Natural paragraph '+i+'.\r';a.paragraphs.everyItem().appliedParagraphStyle=style;fs[0].geometricBounds=[26,14.5,150,100];fs[1].geometricBounds=[26,107,150,192.5];d.recompose();
  check(!a.overflows,'BALANCE_FIXTURE_OVERFLOW');var balanceText=String(a.contents);check(JournalLayout.balanceLastPage(d,a),'NATURAL_BALANCE_FAILED');check(String(a.contents)===balanceText&&!a.overflows,'BALANCE_TEXT_CHANGED');for(i=0;i<a.paragraphs.length;i++)check(a.paragraphs[i].startParagraph!==StartParagraph.NEXT_COLUMN,'BALANCE_CREATED_FORCED_BREAK');
  d.saveACopy(File(NativeGapEvidenceDirectory+'/自然平衡_result_QA.indd'));
  result={passed:true,manualPreserved:true,automaticReleased:true,rollbackVerified:true,otherArticleUnchanged:true,resizeDidNotReintroduceBreak:true,naturalTailBalance:true,fullArticleAcceptance:false,blocked:blocked,solved:solved};
 }catch(e){result={passed:false,error:String(e),line:e.line};}
 finally{if(d&&d.isValid)d.close(SaveOptions.NO);app.scriptPreferences.userInteractionLevel=ui;app.scriptPreferences.enableRedraw=redraw;}
 for(var j=0;j<existing.length;j++)if(!app.documents.itemByID(existing[j]).isValid){result.passed=false;result.error='EXISTING_DOCUMENT_CLOSED';}
 var f=File(NativeGapEvidenceDirectory+'/result.json');f.encoding='UTF-8';f.open('w');f.write(JournalRegressionSnapshot.json(result));f.close();
 return JournalRegressionSnapshot.json(result);
})();
