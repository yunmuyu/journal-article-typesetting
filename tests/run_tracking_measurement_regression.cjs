const assert=require('node:assert/strict');
const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const {test}=require('node:test');
function collection(items){items[-1]=items.at(-1);items.everyItem=()=>({getElements:()=>items.slice()});return items;}
function fixture(failOnce=false,orphanUntil=0,restoreMode=''){
 const frame={id:10,geometricBounds:[26,0,265,85.5]},current=[2.5390625,0],original=[...current];
 const characters=collection(Array.from({length:80},(_,index)=>({index,leading:15})));
 const ps=[0,40].map((start,i)=>{
  const chars=collection(characters.slice(start,start+40));
  const range={characters:chars,appliedFont:{name:'test-font'},get tracking(){return current[i];}};
  const p={contents:'x'.repeat(39)+'\r',characters:chars,insertionPoints:[{index:start}],tables:[],
   appliedParagraphStyle:{name:'正文'},textStyleRanges:collection([range])};
  Object.defineProperty(p,'tracking',{get:()=>current[i],set:v=>{current[i]=v;}});
  chars.forEach(c=>c.paragraphs=[p]);return p;
 });
 characters.itemByRange=(a,b)=>({set tracking(v){for(let i=a;i<=b;i++)current[i<40?0:1]=v;}});
 function line(p,a,b,baseline){
  return {insertionPoints:collection([{index:a,parentTextFrames:[frame]},{index:b,parentTextFrames:[frame]}]),
   characters:collection(characters.slice(a,b)),paragraphs:[p],baseline,contents:ps.indexOf(p)+':'+a};
 }
 const story={contents:ps.map(p=>p.contents).join(''),characters,textContainers:[frame],paragraphs:ps,
  overflows:false,extractLabel:()=> 'body'};
 let injected=false,calls=0,wasTrial=false,settling=0;
 const d={stories:[story],recompose(){
  calls++;
  const isOriginal=current.every((v,i)=>v===original[i]);
  if(!isOriginal)wasTrial=true;
  else if(wasTrial){settling=2;wasTrial=false;}
  if(restoreMode==='bounds'&&!isOriginal)frame.geometricBounds=[26,0,266,85.5];
  if(failOnce&&!injected&&current.includes(-20)){injected=true;throw Error('TEST_COMPOSE_FAILURE');}
  // Both targets changing together would make the measurement depend on another trial.
  assert.ok(current.some((v,i)=>v===original[i]),'probe each paragraph with other current settings preserved');
  frame.lines=collection([]);
  ps.forEach((p,i)=>{
   const delta=current[i]>= (i===0?2.5:30)?1:current[i]<= (i===0?-8.75:-10.1)?-1:0;
   const count=4+delta,start=i*40;
   p.lines=collection(Array.from({length:count},(_,j)=>line(p,start+Math.floor(j*40/count),start+Math.floor((j+1)*40/count),30+frame.lines.length*5+j*5)));
   frame.lines.push(...p.lines);
  });
  frame.lines[-1]=frame.lines.at(-1);
  if(isOriginal&&restoreMode==='delayed'&&settling>0){frame.lines[0].baseline+=.01;settling--;}
  if(isOriginal&&restoreMode==='persistent'&&injected)frame.lines[0].baseline+=.01;
  if(isOriginal&&restoreMode==='persistent-flow'&&settling>0)frame.lines[0].baseline+=.01;
 }};
 const context=vm.createContext({JournalLayout:{
  last:f=>f.lines.at(-1).baseline,visibleBottom:f=>f.lines.at(-1).baseline+.4,
  orphanLine:()=>orphanUntil>0&&current[0]>=2.5&&current[0]<orphanUntil,protectedTokens:()=>[]
 }});
 vm.runInContext(fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_layout_measurement.jsxinc'),'utf8'),context);
 d.recompose();
 return {d,api:context.JournalLayoutMeasurement,current,original,requests:ps.map((p,i)=>({start:i*40,text:p.contents})),calls:()=>calls};
}
test('fresh probes retain existing nonzero tracking and refine both directions',()=>{
 const f=fixture(),before=f.api.flowSignature(f.d.stories[0]);
 const r=f.api.probeTracking(f.d,f.requests);
 assert.deepEqual(f.current,f.original);assert.equal(f.api.flowSignature(f.d.stories[0]),before);
 assert.equal(r[0].currentTracking,2.5390625);assert.equal(r[0].currentLines,5);assert.equal(r[0].baseLines,4);
 assert.equal(r[0].current.lineDelta,1);assert.equal(r[0].current.currentLineDelta,0);
 const positive=r[0].outcomes.find(o=>o.minimumWithin&&o.lineDelta===1);
 const negative=r[0].outcomes.find(o=>o.minimumWithin&&o.lineDelta===-1);
 assert.equal(positive.tracking,2.5);assert.equal(negative.tracking,-8.75);
 const other=r[1].outcomes.find(o=>o.minimumWithin&&o.lineDelta===-1);
 assert.ok(other.tracking<=-10.1&&other.tracking>-10.14);
 assert.equal(r[1].outcomes.some(o=>o.lineDelta===1),false);
});
test('composition failure restores all original tracking and composed flow',()=>{
 const f=fixture(true),before=f.api.flowSignature(f.d.stories[0]);
 assert.throws(()=>f.api.probeTracking(f.d,f.requests),/TEST_COMPOSE_FAILURE/);
 assert.deepEqual(f.current,f.original);assert.equal(f.api.flowSignature(f.d.stories[0]),before);
});
test('stale source text is rejected before any mutation',()=>{
 const f=fixture();f.requests[1].text='changed';
 assert.throws(()=>f.api.probeTracking(f.d,f.requests),/TRACKING_SOURCE_CHANGED/);
 assert.deepEqual(f.current,f.original);assert.equal(f.calls(),1);
});
test('an orphan at the first extra-line threshold does not force the maximum tracking',()=>{
 const f=fixture(false,5),r=f.api.probeTracking(f.d,[f.requests[0]]);
 const usable=r[0].outcomes.filter(o=>o.lineDelta===1&&o.orphanFree).sort((a,b)=>a.tracking-b.tracking)[0];
 assert.ok(usable.tracking>=5&&usable.tracking<5.04);
 assert.deepEqual(f.current,f.original);
});


test('delayed composed flow gets at most three strict restore passes with auditable differences',()=>{
 const f=fixture(false,0,'delayed'),before=f.api.flowSignature(f.d.stories[0]);
 const r=f.api.probeTracking(f.d,[f.requests[0]]);
 assert.equal(r[0].restoreAttempts,3);assert.equal(r[0].restoreDiagnostics.length,2);
 assert.match(r[0].restoreDiagnostics[0],/line 10\/0 start:end:baseline:leading/);
 assert.equal(f.api.flowSignature(f.d.stories[0]),before);assert.deepEqual(f.current,f.original);
});

test('original frame bounds are restored per paragraph as well as tracking',()=>{
 const f=fixture(false,0,'bounds'),before=f.api.flowSignature(f.d.stories[0]);
 f.api.probeTracking(f.d,f.requests);
 assert.deepEqual(f.d.stories[0].textContainers[0].geometricBounds,[26,0,265,85.5]);
 assert.equal(f.api.flowSignature(f.d.stories[0]),before);assert.deepEqual(f.current,f.original);
});

test('persistent baseline drift retains paragraph and exact line diagnostics through final cleanup',()=>{
 const f=fixture(false,0,'persistent-flow');
 assert.throws(()=>f.api.probeTracking(f.d,[f.requests[0]]),error=>{
  assert.match(error.message,/TRACKING_PROBE_RESTORE_CHANGED_FLOW paragraph start=0/);
  assert.match(error.message,/line 10\/0 start:end:baseline:leading/);
  assert.match(error.message,/attempt 3/);assert.match(error.message,/FINAL_RESTORE/);return true;
 });
 assert.deepEqual(f.current,f.original);
});

test('final restore failure preserves the original composition failure',()=>{
 const f=fixture(true,0,'persistent');
 assert.throws(()=>f.api.probeTracking(f.d,[f.requests[0]]),error=>{
  assert.match(error.message,/TEST_COMPOSE_FAILURE/);assert.match(error.message,/FINAL_RESTORE/);
  assert.match(error.message,/TRACKING_PROBE_RESTORE_CHANGED_FLOW final/);return true;
 });
 assert.deepEqual(f.current,f.original);
});
