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
console.log('PASS bounded pull/push decisions, insufficient-budget pruning, collision rejection, rollback, time limit and unresolved-gap gate');
