const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const {build}=require('../2-导入_InDesign/journal_reflow_plan.cjs');
const line=(start)=>({start,end:start+10,paragraphStart:start<100?0:100,text:'ten letters',role:'body',leading:15,baseline:30,ascent:3,descent:.5});
const frames=[0,1,2,3].map((index)=>({index,id:10+index,pageIndex:Math.floor(index/2),bounds:[26,index%2*92,265,85.5+index%2*92],endpoint:[index<2?index*20:100+(index-2)*20,index<2?(index+1)*20:120+(index-2)*20],bottomMm:index===0?264.34:index===1?260:index===2?80:70,targetBottomMm:index<2?264.34:100,lines:[line(index<2?index*20:100+(index-2)*20),line(index<2?index*20+10:110+(index-2)*20)]}));
const m={schemaVersion:1,documentId:1,storyId:2,flowSignature:'synthetic',frames,trackingProbes:[],paragraphs:[{start:100,text:'final paragraph',role:'body',firstFrameId:12,lastFrameId:13}]};
const bottom={columns:[{id:'10',status:'ready'},{id:'11',status:'blocked',requiredDeltaPt:12}],deferred:[]};
assert.ok(build(m,bottom).leadingExpansion.length,'normal continuation retains previous expansion behavior');
bottom.deferred=[{kind:'final-pair',frames:[2,3],reason:'NO_ADJUSTMENT_CAPACITY_INTERSECTION'}];
let p=build(m,bottom);assert.equal(p.leadingExpansion.length,0,'unmeasured earlier expansion cannot repeatedly starve final-page tracking probes');
const states=frames.map(f=>({id:f.id,endpoint:f.endpoint,bottomMm:f.bottomMm,inkBottomMm:f.bottomMm+.5,leadingDownMm:1,leadingUpMm:2}));
const outcomeStates=structuredClone(states);outcomeStates[2].bottomMm=71;outcomeStates[2].inkBottomMm=71.5;
m.trackingProbes=[{probeVersion:2,start:100,text:'final paragraph',context:'source formatting',currentTracking:0,currentFrames:states,outcomes:[{tracking:-5,currentLineDelta:-1,lineCount:3,orphanFree:true,tokenBreakFree:true,overflows:false,frames:outcomeStates}]}];
p=build(m,bottom);assert.equal(p.tracking.length,1);assert.equal(p.tracking[0].target,'final-pair:2,3');assert.equal(p.tracking[0].tracking,-5);
outcomeStates[0].endpoint=[1,20];assert.equal(build(m,bottom).tracking.length,0,'pre-final-page text boundaries remain protected');
function list(a){a[-1]=a.at(-1);return a;}
const page={id:20};class TextFrame{constructor(id){this.id=id;this.parentPage=page;this._bounds=[26,0,265,85.5];this.lines=list([{insertionPoints:list([{index:id===10?0:10},{index:id===10?10:20}])}]);}get geometricBounds(){return this._bounds.slice()}set geometricBounds(v){this._bounds=v.slice()}}
const liveFrames=[new TextFrame(10),new TextFrame(11)],body={id:2,contents:'unchanged source',paragraphs:[],characters:[],textContainers:liveFrames,overflows:false,extractLabel:()=> 'body'};
const d={id:1,stories:[body],allPageItems:liveFrames,pages:list([page]),recompose(){}};
const ctx=vm.createContext({});vm.runInContext(fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_reflow.jsxinc'),'utf8'),ctx);
const plan={schemaVersion:1,documentId:1,storyId:2,tracking:[],leadingCompression:[],leadingExpansion:[],lastPageBalance:{frameIds:[10,11],maximumBottomMm:265}};
ctx.JournalReflow.apply(d,plan,()=>[]);const bounds=liveFrames.map(f=>f.geometricBounds.slice());
assert.throws(()=>ctx.JournalReflow.apply(d,plan,()=>[]),/REFLOW_NO_PROGRESS/);assert.deepEqual(liveFrames.map(f=>f.geometricBounds),bounds);assert.equal(body.contents,'unchanged source');
console.log('PASS final-page probe priority, verified one-line tracking, prefix protection and repeated compaction no-progress rollback');
