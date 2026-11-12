const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path'),assert=require('node:assert/strict');
const ctx={};vm.createContext(ctx);vm.runInContext(fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_gap_solver.jsxinc'),'utf8'),ctx);const S=ctx.JournalGapSolver;
const copy=x=>JSON.parse(JSON.stringify(x));
function fixture({budgets=[3,5],up=0,result='pull',failure=false,unsafe=false,slow=false}={}){
 let current=null,restores=0,applications=0,time=0;
 const columns=budgets.map((budget,i)=>({id:i+1,pageName:String(200+Math.floor(i/2)),blankMm:i===budgets.length-1?40:3,hasLaterContent:true,nextBlock:{startIndex:100+i,minimumAdvanceMm:46,kind:'formula'},adjustments:[{key:'l'+i,kind:'leading',target:{start:i*10,end:i*10+9},from:15,min:14.8,max:16,downMm:budget,upMm:up,costWeight:1}]}));
 columns.push({id:99,blankMm:60,hasLaterContent:false,adjustments:[],nextBlock:null});
 const baseline={columns,hardErrors:[],overlaps:[]};
 const adapter={now(){return time;},snapshot(){return {value:current};},
  apply(candidate){applications++;current=candidate;if(slow)time+=1000;if(failure)throw Error('COMPOSE_FAILED');},
  measure(){const state=copy(baseline);if(current){const target=state.columns[budgets.length-1];if(current.mode===result)target.blankMm=4;if(unsafe)state.hardErrors=['new-overlap'];}return state;},
  validate(saved,state,candidate){return state.hardErrors;},
  restore(saved){restores++;current=saved.value;},
  blockInFrame(){return !!current&&current.mode==='pull'&&result==='pull';}};
 return {adapter,stats:()=>({current,restores,applications})};
}
{
 const f=fixture(),report=S.solve(f.adapter,{maxBoundaries:1});assert.equal(report.status,'gap-check-passed');assert.equal(report.decisions[0].selected.mode,'pull');assert.equal(report.decisions[0].selected.firstFrame,0);assert.ok(report.decisions[0].skipped.some(s=>s.firstFrame===1&&s.mode==='pull'));assert.ok(report.trialCount<=6);assert.ok(f.stats().restores===report.trialCount);assert.equal(report.fullArticleAcceptance,false);
}
{
 const f=fixture({budgets:[0,0]}),r=S.solve(f.adapter,{maxBoundaries:1});assert.equal(r.status,'blocked-large-gaps');assert.equal(r.trialCount,0);assert.equal(f.stats().applications,0);assert.equal(r.appliedDecisions,0);
}
{
 const f=fixture({budgets:[0,0],up:40,result:'push'}),r=S.solve(f.adapter,{maxBoundaries:1});assert.equal(r.status,'gap-check-passed');assert.equal(r.decisions[0].selected.mode,'push');
}
for(const flags of [{failure:true},{unsafe:true}]){
 const f=fixture(flags),r=S.solve(f.adapter,{maxBoundaries:1});assert.equal(r.appliedDecisions,0);assert.equal(r.status,'blocked-large-gaps');assert.equal(f.stats().current,null);assert.ok(r.decisions[0].trials.every(t=>t.errors.length));
}
{
 const f=fixture({slow:true,budgets:[3,5,9],up:40}),r=S.solve(f.adapter,{maxBoundaries:1,maxMilliseconds:100});assert.equal(r.timedOut,true);assert.ok(r.trialCount<=1);assert.equal(r.appliedDecisions,1);
}
assert.throws(()=>S.options({maxCandidates:7}),/INVALID/);assert.throws(()=>S.options({maxWindowFrames:5}),/INVALID/);assert.throws(()=>S.options({maxMilliseconds:NaN}),/INVALID/);
{
 const f=fixture({budgets:[0,0,12]}),measure=f.adapter.measure;
 f.adapter.measure=()=>{
   const state=measure();
   state.columns.forEach((column,index)=>{column.pageIndex=index<2?0:1;});
   state.columns[1].blankMm=20;
   return state;
 };
 const report=S.solve(f.adapter,{orderedPages:true,maxBoundaries:4});
 assert.equal(report.status,'blocked-large-gaps');
 assert.deepEqual(Array.from(report.decisions, decision=>decision.frameId),[2]);
 assert.equal(report.trialCount,0,'later fixable page must wait for earlier blocked page');
}
console.log('PASS bounded pull/push decisions, insufficient-budget pruning, collision rejection, rollback, time limit and unresolved-gap gate');
vm.runInContext(fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_bitmap_gap_trial.jsxinc'),'utf8'),ctx);
const captionAdvance=19*25.4/72;
const scales=ctx.JournalBitmapGapTrial.scaleChoices(42.914,45.551,.75,captionAdvance);
assert.ok(scales.length>1);
assert.ok(scales[0]<.8 && scales[1]<scales[0]);
assert.ok(Array.from(scales).every(scale=>scale>=.75));
assert.equal(ctx.JournalBitmapGapTrial.scaleChoices(20,45.551,.75,captionAdvance).length,0);
console.log('PASS bitmap trials are bounded by measured gap and minimum scale');

{
 const page = {name:'4',documentOffset:3};
 const frame = {parentPage:page,textFramePreferences:{textColumnCount:2},geometricBounds:[0,0,100,100]};
 const left = {baseline:60,descent:0,insertionPoints:{'-1':{index:5}}};
 const right = {insertionPoints:[{index:15}]};
 ctx.JournalLayout = {nativeFlowBands:()=>({bands:[{left:[left],right:[right]}]})};
 const anchor = {index:10,leading:15,contents:'\uFFFC'};
 const body = {id:1,textContainers:[frame],paragraphs:[anchor,{leading:15},{leading:15,contents:'图 1 合成图'}]};
 class Character {
   constructor(story, paragraph) {
     this.parentStory = story;
     this.paragraphs = [paragraph];
   }
 }
 const item = {
   label:'source-figure-1',parentPage:page,parent:new Character({id:2},anchor),
   geometricBounds:[0,60,100,80],graphics:[{itemLink:{name:'synthetic.png'}}]
 };
 const document = {allPageItems:[item]};
 const run = () => ctx.JournalBitmapGapTrial.run(document,body,{},'4',false).reason;
 assert.equal(run(),'NO_BITMAP_AT_COLUMN_BOUNDARY','same page and figure number cannot authorize a foreign story item');
 item.parent = new Character(body,{index:11});
 assert.equal(run(),'NO_BITMAP_AT_COLUMN_BOUNDARY','the anchor must belong to the paragraph bound to the caption');
 item.parent = new Character(body,anchor);
 assert.equal(run(),'BITMAP_CANNOT_FIT_WITHIN_LIMIT','the matching anchor proceeds to the normal scale gate');

 const nextPage = {id:5,documentOffset:4};
 const stack = [
   {contents:'见图1、2'}, {contents:'\uFFFC'}, {}, {contents:'图 1 合成图'},
   {contents:'\uFFFC'}, {}, {contents:'图 2 合成图'}, {appliedParagraphStyle:{name:'二级标题'}},
   {contents:'正文',appliedParagraphStyle:{name:'正文'}}, {contents:'\uFFFC'}, {}, {contents:'图 3 合成图'}
 ].map((paragraph,index)=>({...paragraph,index}));
 const nextLine = {insertionPoints:[{index:1}]};
 body.textContainers.push({parentPage:nextPage,lines:[nextLine]});
 body.paragraphs = stack;
 right.baseline = 80;
 ctx.JournalLayout.rules = {bottomInset:0};
 document.allPageItems = [
   {...item,parentPage:nextPage,parent:new Character({id:2},stack[1])},
   {...item,label:'source-figure-2',parentPage:nextPage,parent:new Character(body,stack[4])},
   {...item,label:'source-figure-3',parentPage:nextPage,parent:new Character(body,stack[9])}
 ];
 const defer = () => ctx.JournalBitmapGapTrial.deferStack(document,body,{},'4').reason;
 assert.equal(defer(),'NO_TWO_FIGURE_STACK','a foreign figure cannot authorize deferring a text range');
 nextLine.insertionPoints[0].index = 0;
 assert.equal(defer(),'STACK_NOT_REFERENCED_BEFORE_INSERTION','the story start has no preceding reference paragraph');
 console.log('PASS bitmap trial only considers anchors in the target story and matching figure paragraph');
}
