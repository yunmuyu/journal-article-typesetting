const fs=require('fs'),p=require('path'),vm=require('vm'),assert=require('node:assert/strict');
const root=p.resolve(__dirname,'../2-导入_InDesign');
const ctx={Position:{NORMAL:0,SUPERSCRIPT:1,SUBSCRIPT:2},FontStatus:{INSTALLED:1},app:{fonts:{itemByName:n=>({name:n,isValid:true,status:1}),everyItem:()=>({getElements:()=>[{name:'Times New Roman\\tItalic',fontFamily:'Times New Roman',postscriptName:'TimesNewRomanPS-ItalicMT',status:1}]})}}};vm.createContext(ctx);
for(const name of ['journal_layout_rules.jsxinc','journal_frontmatter.jsxinc','journal_article_assembly.jsxinc'])vm.runInContext(fs.readFileSync(p.join(root,name),'utf8'),ctx);
const R=ctx.JournalLayout;
assert.equal(R.formulaPlacementAllowed({kind:'formula'},{}),false);
assert.equal(R.formulaPlacementAllowed({kind:'formula',placement:'native-vector'},{}),true);
assert.equal(R.formulaPlacementAllowed({kind:'formula'},{legacyRegressionFixture:true}),true);
assert.equal(R.forbiddenLineStart('，接续文字'),true);assert.equal(R.forbiddenLineStart('\t，'),true);assert.equal(R.forbiddenLineStart('\uFFFC，'),false);
assert.equal(R.sourceProjection('f ⟦EQ-003⟧ φ_i').text,'fφ_i');
const text='式中，f为输入；\uFFFCΩ为积分域。\r',chars=Array.from(text).map(contents=>({contents,position:0,fontStyle:'Regular'}));
const paragraph={contents:text,characters:chars,appliedParagraphStyle:{name:'正文'}};
const d={stories:[{paragraphs:[paragraph],extractLabel:()=> 'body'}]};
const source='式中，f为输入；⟦EQ-003⟧Ω为积分域。';
const c={sourceTextFormatting:[{role:'body',text:source,runs:[{start:3,end:4,italic:true},{start:source.indexOf('Ω'),end:source.indexOf('Ω')+1,position:'subscript',italic:true}]}]};
assert.ok(R.sourceTextFormatting(d,c,false).some(x=>x.includes('ITALIC')));
assert.ok(R.sourceTextFormatting(d,c,false).some(x=>x.includes('POSITION')));
assert.equal(R.sourceTextFormatting(d,c,true).length,0);assert.equal(R.sourceTextFormatting(d,c,false).length,0);
assert.equal(chars[3].fontStyle,'Italic');assert.equal(chars[text.indexOf('Ω')].position,2);
const F=ctx.JournalFrontmatter;assert.equal(F.englishStyleContract('enAffiliation',{leading:25,spaceBefore:0,spaceAfter:2}).leading,25);assert.equal(F.englishStyleContract('enTitle',{leading:22,spaceBefore:3,spaceAfter:4}).leading,22);assert.equal(F.englishStyleContract('enAbstract',{leading:13,spaceBefore:0,spaceAfter:0}).leading,13);
assert.equal(ctx.JournalArticleAssembly.printedFormulaNumber({},17),null);assert.equal(ctx.JournalArticleAssembly.printedFormulaNumber({displayNumbers:{17:'3'}},17),'3');
console.log('PASS default native formulas, exact source italic/subscript mapping past markers, punctuation starts, front role leading, source-only numbering');

assert.equal(R.removableHeadingBlank('\r',15,0,0,'h1'),true);assert.equal(R.removableHeadingBlank('\r',.1,0,0,'h1'),false);assert.equal(R.removableHeadingBlank('\uFFFC\r',15,0,1,'h1'),false);

vm.runInContext(fs.readFileSync(p.join(root,'journal_reflow.jsxinc'),'utf8'),ctx);
let lead=15,owner={parentPage:{documentOffset:3}};
const range={characters:{0:{index:0},'-1':{index:9}},leading:15};
const pbody={contents:'complete boundary',appliedParagraphStyle:{name:'正文'},insertionPoints:{0:{index:0,parentTextFrames:[owner]},'-2':{parentTextFrames:[owner]}},tables:[],textStyleRanges:{everyItem:()=>({getElements:()=>[range]})},get leading(){return lead},set leading(v){lead=v}};
const cap={contents:'caption',appliedParagraphStyle:{name:'图注/表名'},insertionPoints:{0:{index:20}},leading:14};
const earlier={contents:'earlier page',appliedParagraphStyle:{name:'正文'},insertionPoints:{0:{index:-10,parentTextFrames:[{parentPage:{documentOffset:0}}]},'-2':{parentTextFrames:[{parentPage:{documentOffset:0}}]}},tables:[],leading:14.9};
const fakeBody={textContainers:[],contents:'complete boundary\rcaption',paragraphs:[earlier,pbody,cap],characters:{itemByRange:()=>({})}};
const result=ctx.JournalReflow.fillBeforePanel({recompose(){owner.parentPage.documentOffset=lead<=15.6?3:4}},fakeBody,'complete boundary',4);
assert.ok(result.leading>15.59&&result.leading<=15.6);assert.equal(earlier.leading,14.9);assert.equal(cap.leading,14);assert.equal(fakeBody.contents,'complete boundary\rcaption');


assert.equal(ctx.JournalArticleAssembly.printedFormulaNumber({},17,"   （2）"),"2");

const missing={sourceTextFormatting:[{role:'body',text:'missing source paragraph',runs:[{start:0,end:1,italic:true}]}]};assert.ok(R.sourceTextFormatting(d,missing,false)[0].includes('COUNT'));chars[4].position=2;assert.ok(R.sourceTextFormatting(d,c,false).some(x=>x.includes('POSITION')));R.sourceTextFormatting(d,c,true);assert.equal(chars[4].position,0);

const trackingRequest=require('../2-导入_InDesign/journal_tracking_request.cjs').build;
assert.deepEqual(trackingRequest({frames:[{id:7,index:0,pageIndex:1,targetBottomMm:264},{id:8,index:1,pageIndex:1,targetBottomMm:264}],paragraphs:[{start:1,text:'x'.repeat(40),role:'body',firstFrameId:7,lastFrameId:7},{start:2,text:'x'.repeat(40),role:'caption',firstFrameId:7,lastFrameId:7},{start:3,text:'x'.repeat(40),role:'body',firstFrameId:7,lastFrameId:8}]},{columns:[{id:'7',status:'blocked'}]}).map(x=>x.start),[1,3]);
const assemblySource=fs.readFileSync(p.join(root,'journal_article_assembly.jsxinc'),'utf8');
assert.ok(assemblySource.includes('fillPreceding===true&&spec.keepFollowingAfterPanel===true'));
assert.ok(assemblySource.includes('result.panels=refreshPanels(d,body,job,true)'));

assert.ok(fs.readFileSync(p.join(root,'journal_frontmatter.jsxinc'),'utf8').includes('frame.parentStory.contents = text.join'));
const chooseTracking=require('../2-导入_InDesign/journal_reflow_plan.cjs').trackingChoices;
const suffixFrames=[{index:0,id:10,pageIndex:0,bounds:[26,0,265,85],endpoint:[0,100],targetBottomMm:264.34},{index:1,id:20,pageIndex:1,bounds:[26,0,265,85],endpoint:[100,200],targetBottomMm:264.34},{index:2,id:30,pageIndex:2,bounds:[26,0,100,85],endpoint:[200,300],targetBottomMm:99.34},{index:3,id:40,pageIndex:2,bounds:[26,0,100,85],endpoint:[300,400],targetBottomMm:99.34}];
const suffixOutcome={tracking:2,currentLineDelta:1,lineCount:6,orphanFree:true,tokenBreakFree:true,overflows:false,frames:[{id:10,endpoint:[0,100],bottomMm:260,inkBottomMm:261,leadingDownMm:1,leadingUpMm:5},{id:20,endpoint:[100,210],bottomMm:261,inkBottomMm:261.3,leadingDownMm:1,leadingUpMm:4},{id:30,endpoint:[210,310],bottomMm:90,inkBottomMm:91,leadingDownMm:1,leadingUpMm:1},{id:40,endpoint:[310,400],bottomMm:90,inkBottomMm:91,leadingDownMm:1,leadingUpMm:1}]};
const suffixMeasurement={flowSignature:'synthetic',frames:suffixFrames,paragraphs:[{start:150,firstFrameId:20,lastFrameId:30}],tables:[],trackingProbes:[{probeVersion:2,start:150,text:'synthetic paragraph',currentTracking:0,context:'synthetic',outcomes:[suffixOutcome]}]};
assert.equal(chooseTracking(suffixMeasurement,{columns:[{id:'20',status:'blocked'}]}).selected[0].target,'flow:20');
const changedPrefix=structuredClone(suffixMeasurement);changedPrefix.trackingProbes[0].outcomes[0].frames[0].endpoint=[0,99];assert.equal(chooseTracking(changedPrefix,{columns:[{id:'20',status:'blocked'}]}).selected.length,0);
const changedEnd=structuredClone(suffixMeasurement);changedEnd.trackingProbes[0].outcomes[0].frames[3].endpoint=[310,399];assert.equal(chooseTracking(changedEnd,{columns:[{id:'20',status:'blocked'}]}).selected.length,0);

const expandableFinal=structuredClone(suffixMeasurement),expandedOutcome=expandableFinal.trackingProbes[0].outcomes[0];expandedOutcome.finalPageExpansion=true;expandedOutcome.frames[2].endpoint=[210,400];expandedOutcome.frames[3].endpoint=null;expandedOutcome.frames[2].bottomMm=120;expandedOutcome.frames[2].inkBottomMm=120.3;expandedOutcome.frames[3].bottomMm=NaN;expandedOutcome.frames[3].inkBottomMm=NaN;
assert.equal(chooseTracking(expandableFinal,{columns:[{id:'20',status:'blocked'}]}).selected[0].finalPageExpansion,true);
expandedOutcome.overflows=true;assert.equal(chooseTracking(expandableFinal,{columns:[{id:'20',status:'blocked'}]}).selected.length,0);

const incremental=structuredClone(suffixMeasurement),incrementProbe=incremental.trackingProbes[0];incrementProbe.lastFrameId=20;incremental.paragraphs[0].lastFrameId=20;incrementProbe.currentFrames=structuredClone(suffixOutcome.frames);incrementProbe.currentFrames[1].endpoint=[100,200];incrementProbe.currentFrames[1].bottomMm=260;incrementProbe.currentFrames[1].inkBottomMm=260.3;incrementProbe.currentFrames[1].leadingUpMm=1;
const incrementalOutcome=incrementProbe.outcomes[0];incrementalOutcome.frames[1].endpoint=[100,200];incrementalOutcome.frames[1].bottomMm=261;incrementalOutcome.frames[1].inkBottomMm=261.3;incrementalOutcome.frames[1].leadingUpMm=1;incrementalOutcome.frames[2].endpoint=[200,300];incrementalOutcome.frames[3].endpoint=[300,400];
const incrementalChoice=chooseTracking(incremental,{columns:[{id:'20',status:'blocked'}]}).selected[0];assert.equal(incrementalChoice.capacityProgress,true);
const noImprovement=structuredClone(incremental);noImprovement.trackingProbes[0].outcomes[0].frames[1].bottomMm=259;noImprovement.trackingProbes[0].outcomes[0].frames[1].inkBottomMm=259.3;assert.equal(chooseTracking(noImprovement,{columns:[{id:'20',status:'blocked'}]}).selected.length,0);

const padding={id:99,label:'formula-layout-padding',fillColor:{name:'None'},strokeColor:{name:'inherited gray'},getElements(){return [this]},applyObjectStyle(){this.styleCleared=true},set properties(value){Object.assign(this,value)}};
const realInk={id:100,label:'',fillColor:{name:'black'},strokeColor:{name:'black'}};
const paddingDocument={allPageItems:[padding,realInk],objectStyles:[{}],swatches:{itemByName:name=>({name})}};
assert.equal(R.formulaPadding(paddingDocument,false).length,1);assert.equal(R.formulaPadding(paddingDocument,true).length,0);assert.equal(padding.styleCleared,true);assert.equal(realInk.strokeColor.name,'black');

for(const name of fs.readdirSync(root).filter(n=>/\.jsx(?:inc)?$/.test(n)))assert.ok(!/\b(?:var|function)\s+(?:native|abstract|boolean|byte|char|double|final|float|goto|int|long|short|synchronized|throws|transient|volatile)\b/.test(fs.readFileSync(p.join(root,name),'utf8')),name+' uses an ExtendScript reserved name');
function formulaLine(a,b){const chars=[{index:a,leading:30},{index:b,leading:30}];chars[-1]=chars[1];chars.everyItem=()=>({set leading(v){chars.forEach(c=>c.leading=v)}});return {characters:chars};}
const mathParagraph={index:10,contents:'\uFFFC，\uFFFC\r',lines:[formulaLine(10,11),formulaLine(12,13)]};
function nativeMath(index,height){return {extractLabel:()=>'',label:'source-formula-'+index,parent:{constructor:{name:'Character'},index,parentStory:{id:1},paragraphs:[mathParagraph]},geometricBounds:[0,0,height,20]};}
const lineDocument={allPageItems:[nativeMath(10,9),nativeMath(12,4)],recompose(){}};
assert.equal(R.formulaLineSpacing(lineDocument,false).length,2);R.formulaLineSpacing(lineDocument,true);assert.equal(R.formulaLineSpacing(lineDocument,false).length,0);assert.equal(mathParagraph.lines[1].characters[0].leading,15);assert.ok(mathParagraph.lines[0].characters[0].leading>27);assert.equal(mathParagraph.contents,'\uFFFC，\uFFFC\r');

const largeFormulaParagraph={index:10,contents:'\uFFFC（6）\r',lines:[formulaLine(10,13)]};largeFormulaParagraph.lines[0].characters.forEach(c=>c.leading=105);
const largeFormula=nativeMath(10,30);largeFormula.parent.paragraphs=[largeFormulaParagraph];const largeFormulaDocument={allPageItems:[largeFormula],recompose(){}};
assert.equal(R.formulaLineSpacing(largeFormulaDocument,false).length,1);R.formulaLineSpacing(largeFormulaDocument,true);assert.ok(largeFormulaParagraph.lines[0].characters[0].leading<88);assert.equal(R.formulaLineSpacing(largeFormulaDocument,false).length,0);
assert.ok(fs.readFileSync(p.join(root,'journal_layout_and_check.jsx'),'utf8').includes('cfg.sourceTextFormatting=logical.blocks'));

const inlineLabels={'formula-display':'false','formula-printed-number':''};
const inlineParagraph={index:3,contents:'正文（2）\uFFFC邻字\r',justification:'left',pointSize:10.5};
const inlineAnchor={constructor:{name:'Character'},index:8,parentStory:{id:2},paragraphs:[inlineParagraph],leading:15};
const inlineObject={label:'source-formula-7',parent:inlineAnchor,geometricBounds:[0,0,10,20],extractLabel:k=>inlineLabels[k]||'',insertLabel(k,v){inlineLabels[k]=v}};
const inlineDoc={allPageItems:[inlineObject],recompose(){}};
assert.equal(R.formulaLineSpacing(inlineDoc,false).length,1);R.formulaLineSpacing(inlineDoc,true);assert.equal(R.formulaLineSpacing(inlineDoc,false).length,0);
assert.ok(inlineAnchor.leading>30);assert.equal(inlineParagraph.justification,'left');assert.equal(inlineParagraph.pointSize,10.5);
assert.equal(R.sourceFormulaNumbering(inlineDoc,{formulaNumbers:[{number:7,inline:true,displayNumber:null}]},false).length,0);
assert.equal(inlineParagraph.contents,'正文（2）\uFFFC邻字\r');
assert.ok(R.sourceFormulaNumbering(inlineDoc,{formulaNumbers:[{number:7,inline:true,displayNumber:'2'}]},false).length);
