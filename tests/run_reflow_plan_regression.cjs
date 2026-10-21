const assert=require('node:assert/strict');
const {build,lastPageBalance,trackingChoices}=require('../2-导入_InDesign/journal_reflow_plan.cjs');
const line=(start,baseline)=>({start,end:start+10,paragraphStart:0,baseline,leading:15,ascent:3.5,role:'body'});
const m={schemaVersion:1,documentId:8,storyId:9,flowSignature:'measured',
 frames:[{index:0,id:11,pageIndex:1,bounds:[26,0,265,85.5],endpoint:[0,20],lines:[line(0,30),line(10,35)]},
 {index:1,id:12,pageIndex:1,bounds:[26,92.5,265,178],endpoint:[20,40],lines:[line(20,30),line(30,35)]}],
 paragraphs:[{start:0,text:'A long paragraph',role:'body',firstFrameId:11,lastFrameId:12}],
 trackingProbes:[{probeVersion:2,start:0,text:'A long paragraph',currentTracking:0,context:'current-font-and-tracking',
  outcomes:[{tracking:22,lineDelta:1,orphanFree:true},
 {tracking:8,lineDelta:1,orphanFree:false},{tracking:6.25,lineDelta:1,orphanFree:true}]}]};
for(const o of m.trackingProbes[0].outcomes){
 o.currentLineDelta=o.lineDelta;o.lineCount=5;o.tokenBreakFree=true;o.overflows=false;
 o.frames=m.frames.map(f=>({id:f.id,endpoint:f.endpoint,bottomMm:35,inkBottomMm:35.4,leadingUpMm:0,leadingDownMm:0}));
}
const p=build(m,{columns:[],deferred:[{kind:'local-pair',frames:[0,1]}]});
assert.equal(p.tracking.length,1);
assert.equal(p.tracking[0].tracking,6.25);
assert.deepEqual(p.lastPageBalance.frameIds,[11,12]);
assert.equal(p.lastPageBalance.allowNormalParagraphContinuation,true);
const compacted=structuredClone(m);
compacted.frames.forEach(f=>f.bounds[2]=100);
compacted.frames.unshift({...structuredClone(m.frames[0]),id:99,pageIndex:0});
assert.equal(lastPageBalance(compacted).maximumBottomMm,265,'a previously compacted final page can grow when earlier flow changes');
assert.equal(p.lastPageCandidates.length,0);
assert.throws(()=>lastPageBalance({...m,frames:[m.frames[0]]}),/TWO_COLUMNS/);
assert.equal(lastPageBalance({...m,frames:[m.frames[0],{...m.frames[1],lines:[]}]}).frameIds.length,2,'an empty final right column can be filled by normal balancing');
assert.throws(()=>lastPageBalance({...m,frames:m.frames.map(f=>({...f,lines:[]}))}),/WITH_CONTENT/);
assert.throws(()=>build({...m,flowSignature:null},{columns:[],deferred:[]}),/PROBE_STALE/);
const borrowing=structuredClone(m);
borrowing.frames[0].bottomMm=259.1;
borrowing.frames[0].targetBottomMm=264.3445;
assert.equal(build(borrowing,{columns:[{id:'11',status:'blocked',bestResidualPt:2}],deferred:[]}).leadingCompression.length,2);
borrowing.frames[1].lines[0].paragraphStart=20;
assert.equal(build(borrowing,{columns:[{id:'11',status:'blocked',bestResidualPt:2}],deferred:[]}).leadingCompression.length,0,'do not pull a new paragraph across keep constraints');
const compress=structuredClone(m);
compress.paragraphs[0].lastFrameId=11;
compress.frames[0].targetBottomMm=30;
compress.trackingProbes[0].outcomes=[-20,-7.5,-4,3].map(value=>({
 tracking:value,currentLineDelta:value<0?-1:1,lineCount:value<0?3:5,
 orphanFree:true,tokenBreakFree:true,overflows:false,
 frames:compress.frames.map(f=>({id:f.id,endpoint:f.endpoint,bottomMm:f.id===11?(value===-4?32:value<0?30:40):35,
  inkBottomMm:35.4,leadingUpMm:0,leadingDownMm:0}))
}));
const target={columns:[{id:'11',status:'blocked',bestResidualPt:-10}],deferred:[]};
let decisions=trackingChoices(compress,target);
assert.equal(decisions.selected[0].tracking,-7.5,'smallest compression that actually solves the measured target');
assert.equal(decisions.selected[0].purpose,'one-fewer-line');
compress.trackingProbes[0].outcomes[1].tokenBreakFree=false;
assert.equal(trackingChoices(compress,target).selected[0].tracking,-20,'reject an illegal token break despite its smaller adjustment');
compress.trackingProbes[0].outcomes[0].frames[1].endpoint=[21,40];
assert.equal(trackingChoices(compress,target).selected.length,0,'do not silently move text in another column');
assert.equal(trackingChoices(m,{columns:[],deferred:[]}).selected.length,0,'do not apply unnecessary tracking when current capacity suffices');
console.log('PASS reflow: fresh bidirectional tracking, minimum feasible adjustment, token/flow exclusions, normal final-page continuation');

const referenceContinuation=structuredClone(m);referenceContinuation.trackingProbes=[];referenceContinuation.frames[0].bottomMm=260;referenceContinuation.frames[0].targetBottomMm=264.3445;for(const f of referenceContinuation.frames)for(const l of f.lines){l.role='reference';l.leading=13;}
const referenceCompression=build(referenceContinuation,{columns:[{id:'11',status:'blocked'}],deferred:[]}).leadingCompression;
assert.equal(referenceCompression.length,2);assert.ok(referenceCompression.every(x=>x.leading===12.6&&x.role==='reference'));

const transfer=structuredClone(m);transfer.trackingProbes=[];transfer.frames[0].bottomMm=264.34;transfer.frames[0].targetBottomMm=264.34;transfer.frames[1].bottomMm=260;transfer.frames[1].targetBottomMm=264.34;for(const f of transfer.frames)for(const l of f.lines)l.text='ten letters';
const transferBottom={columns:[{id:'11',status:'ready'},{id:'12',status:'blocked',requiredDeltaPt:12}],deferred:[]};
const transferPlan=build(transfer,transferBottom);assert.equal(transferPlan.leadingTransfers[0].fromFrameId,11);assert.equal(transferPlan.leadingTransfers[0].toFrameId,12);assert.ok(transferPlan.leadingExpansion.every(x=>x.leading>15&&x.leading<=16));
const otherBand=structuredClone(transfer);otherBand.frames[0].bounds[2]=100;assert.equal(build(otherBand,transferBottom).leadingExpansion.length,0);
