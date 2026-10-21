const assert=require('node:assert/strict');
const {build}=require('../2-导入_InDesign/journal_tracking_request.cjs');
const frames=[{id:10,index:0,pageIndex:0,targetBottomMm:245},{id:11,index:1,pageIndex:0,targetBottomMm:265},{id:12,index:2,pageIndex:1,targetBottomMm:265}];
const p=(start,first,last)=>({start,firstFrameId:first,lastFrameId:last,role:'body',text:'a'.repeat(80)});
const m={frames,paragraphs:[p(1,10,11),p(2,11,12),p(3,12,12),p(4,10,10)]};
assert.deepEqual(build(m,{columns:[{id:11,status:'blocked'}]}).map(x=>x.start),[1,2]);
console.log('PASS incoming cross-column paragraph remains eligible when first-page columns have unequal bottom targets');
