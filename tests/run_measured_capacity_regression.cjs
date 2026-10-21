const assert=require('node:assert/strict');
const {build,tableRows}=require('../2-导入_InDesign/journal_bottom_measurement_request.cjs');
const frame=(id,index,page,bottom,count=20)=>({id,index,pageIndex:page,bounds:[26,14.5,265,100],
  bottomMm:bottom,inkBottomMm:bottom+.4,targetBottomMm:264.344524842923,endpoint:[index*100,index*100+count*2],
  lines:Array.from({length:count},(_,i)=>({role:'body',leading:15,frameId:id,hasTable:false,start:index*100+i*2,end:index*100+i*2+2}))});
const input={schemaVersion:1,documentId:1,storyId:2,overflows:false,localBottomPairs:[],
 frames:[frame(10,0,0,220),frame(11,1,0,262),frame(12,2,1,263),frame(13,3,2,220),frame(14,4,2,218)]};
let result=build(input);
assert.equal(result.columns.length,4);
assert.equal(result.columns[0].leadingGroups.length,19,'20 lines have 19 local baseline intervals');
assert.equal(result.columns[0].leadingGroups.reduce((n,g)=>n+g.maxPt-g.currentPt,0),19);
assert.equal(result.columns[0].leadingGroups[0].target.startIndex,100,'first-line leading controls the following baseline');
assert.equal(result.columns[0].leadingGroups.at(-1).target.startIndex,136,'terminal-line leading belongs to flow after this frame');
assert.equal(result.preservation.frames.length,5,'lock all frames, not only adjusted ones');
input.frames[1].bounds[2]=110;input.frames[2].bounds[2]=110;
input.frames[1].inkBottomMm=100;input.frames[2].inkBottomMm=109;
input.localBottomPairs=[{frames:[1,2]}];
result=build(input);
assert.equal(result.columns.length,2,'reject disjoint local ranges while retaining feasible final pair');
assert.equal(result.deferred[0].reason,'NO_ADJUSTMENT_CAPACITY_INTERSECTION');
input.frames[2].inkBottomMm=101;
result=build(input);
assert.equal(result.columns.length,4);
assert.equal(result.columns[0].targetBottomPt,result.columns[1].targetBottomPt);
input.frames[1].bounds[2]=100;
input.figures=[{pageIndex:input.frames[1].pageIndex,frameId:999,frameBounds:[118.9,0,220,178]}];
result=build(input);
assert.ok(result.frameExpansions.some(e=>e.id===11&&e.toBottomMm>101),'a local table can grow into verified space before the figure without moving frame tops');
assert.ok(result.frameExpansions.find(e=>e.id===11).toBottomMm<102,'unequal column bottoms must not force the shorter frame to the other frame bottom');
input.overflows=true;assert.throws(()=>build(input),/MEASUREMENT_NOT_COMPOSED/);
const tableInput={tables:[{id:1,label:'source-table-1',headerRowCount:1,rows:[{index:0,height:5},{index:1,height:5},{index:2,height:9}],
 cells:[{rowIndex:0,rowSpan:1,lines:[{frameId:11}]},{rowIndex:1,rowSpan:1,lines:[{frameId:11}]},{rowIndex:2,rowSpan:1,lines:[{frameId:11},{frameId:11}]}]}]};
assert.deepEqual(tableRows(input.frames[1],tableInput).map(r=>r.target.rowIndex),[1],'exclude repeated headers and naturally tall rows');
console.log('PASS real-line capacity, whole-flow endpoint guards, infeasible pairs');
const unevenFinal={schemaVersion:1,documentId:1,storyId:2,overflows:false,localBottomPairs:[],
 frames:[frame(21,0,0,262),frame(22,1,1,220),frame(23,2,1,218)]};
unevenFinal.frames[1].bounds[2]=220.5;
const unevenFinalPlan=build(unevenFinal);
assert.ok(!unevenFinalPlan.frameExpansions.some(e=>e.id===22),
 'a final-column cut that already fits its ink must not expand to the other frame bottom and undo the chosen text split');
console.log('PASS preserve deliberate final-page split with unequal frame heights');
