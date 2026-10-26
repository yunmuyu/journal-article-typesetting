const assert=require('node:assert/strict');
const {lastPageCandidates}=require('../2-导入_InDesign/journal_reflow_plan.cjs');
const m={frames:[{pageIndex:0,bounds:[20,0,265,85],endpoint:[0,20],lines:[{start:0,paragraphStart:0,baseline:30,leading:15,ascent:3},{start:10,paragraphStart:10,baseline:35,leading:15,ascent:3}]},{pageIndex:0,bounds:[20,90,265,175],endpoint:[20,30],lines:[{start:20,paragraphStart:20,baseline:30,leading:15,ascent:3}]}],paragraphs:[{start:0,role:'body'},{start:10,role:'h1',keepWithNext:0},{start:20,role:'body',text:'following text'}]};
assert.equal(lastPageCandidates(m).length,1,'complete h1 may remain at column end when it does not keep next');
m.paragraphs[2].role='h2';assert.equal(lastPageCandidates(m).length,1,'h1 can end the left column while complete h2 and its following text begin the right');
for(const role of ['h2','referenceTitle']){m.paragraphs[1].role=role;assert.equal(lastPageCandidates(m).length,0);}
m.paragraphs[1].role='h1';m.paragraphs[1].keepWithNext=1;assert.equal(lastPageCandidates(m).length,0,'explicit keep must be respected');
console.log('PASS heading boundary respects explicit keep and permits complete h1');
