const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const ctx=vm.createContext({StartParagraph:{ANYWHERE:0,NEXT_COLUMN:1},JournalRegressionSnapshot:{json:JSON.stringify}});
for(const file of ['journal_gap_solver.jsxinc','journal_gap_layout.jsxinc'])vm.runInContext(fs.readFileSync('2-导入_InDesign/'+file,'utf8'),ctx);
// Given two article bodies, When the second is bound, Then no global role lookup is used.
function story(id){return {id,allPageItems:[],tables:[],textContainers:[],contents:'stable',overflows:false,extractLabel:()=> 'body',getElements(){return [this];}};}
const a=story(1),b=story(2),stories=[a,b];stories.itemByID=id=>stories.find(s=>s.id===id)||{isValid:false};a.isValid=b.isValid=true;
assert.doesNotThrow(()=>ctx.JournalGapLayout.measure({stories,pages:[{}]},{bindings:[{role:'body',id:2}]}),'explicit article body must work in merged issues');
assert.throws(()=>ctx.JournalGapLayout.measure({stories,pages:[{}]},{}),/GAP_BODY_COUNT/);
// Given a forced boundary and no typography budget, When planning, Then release only authorized breaks.
const state={columns:[{id:1,blankMm:80,hasLaterContent:true,adjustments:[],nextBlock:{startIndex:10,minimumAdvanceMm:5,breakControl:{releasable:true,paragraphStart:10,from:1,reason:'automatic'}}}]};
const candidates=ctx.JournalGapSolver.plan(state,0,{}).candidates;
assert.equal(candidates[0].mode,'release-break');
assert.equal(candidates[0].operations[0].kind,'column-break');
state.columns[0].nextBlock.breakControl.releasable=false;
assert(!ctx.JournalGapSolver.plan(state,0,{}).candidates.some(c=>c.mode==='release-break'));
console.log('PASS bound article scope and authorized structural break candidate without typography budget');

// Given ownership, When an explicit human protection exists, Then it wins over automatic provenance.
let labels='';const p={index:10,contents:'[1] stable reference',startParagraph:1};
const owned={id:2,paragraphs:[p],extractLabel:()=>labels,insertLabel:(k,v)=>labels=v};
ctx.JournalGapLayout.registerAutomaticBreak(owned,p);
assert.equal(ctx.JournalGapLayout.breakControl(owned,p,{}).releasable,true);
assert.equal(ctx.JournalGapLayout.breakControl(owned,p,{protectedColumnBreaks:[{storyId:2,paragraphStart:10,text:p.contents}]}).releasable,false);
p.contents='edited reference';assert.equal(ctx.JournalGapLayout.breakControl(owned,p,{}).releasable,false);
assert.equal(ctx.JournalGapLayout.breakControl(owned,p,{legacyAutomaticBreaks:[{storyId:2,paragraphStart:9,text:p.contents}]}).releasable,false);
console.log('PASS human protection and stale migration identity cannot release unrelated paragraphs');

state.columns[0].blankMm=.2;state.columns[0].nextBlock.breakControl.releasable=true;assert.equal(ctx.JournalGapSolver.plan(state,0,{}).candidates[0].mode,'release-break');assert.equal(ctx.JournalGapSolver.score(state,ctx.JournalGapSolver.options({}),0)[0],1);console.log('PASS compacted frame does not hide stale automatic break');
const incomplete={columns:[{id:6,pageName:'315',hasLaterContent:true,blankMm:61.823,nextBlock:null},{id:14,pageName:'318',hasLaterContent:true,blankMm:.146,nextBlock:{breakControl:{releasable:true}}}]};assert.equal(ctx.JournalGapSolver.unresolved(incomplete,ctx.JournalGapSolver.options({})).length,2);console.log('PASS residual report includes both large gaps and stale breaks in compacted frames');