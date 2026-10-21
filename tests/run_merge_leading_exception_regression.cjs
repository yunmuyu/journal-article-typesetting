const assert=require('node:assert/strict'),{rangeLeadingLimits}=require('../2-导入_InDesign/journal_regression_contract.cjs');
const p={group:'body',startIndex:8},r={start:0,text:'abc'},c={bindings:[{role:'body',id:123}],leadingExceptions:[{storyId:123,startIndex:0,endIndex:171,minPt:14.7,userApproved:true,reason:'approved'}]};
assert.deepEqual(rangeLeadingLimits([14.8,16],p,r,c),[14.7,16]);
assert.deepEqual(rangeLeadingLimits([14.8,16],{...p,startIndex:172},r,c),[14.8,16]);
assert.deepEqual(rangeLeadingLimits([14.8,16],p,r,{...c,bindings:[{role:'body',id:124}]}),[14.8,16]);
assert.deepEqual(rangeLeadingLimits([14.8,16],p,r,{...c,leadingExceptions:[{...c.leadingExceptions[0],userApproved:false}]}),[14.8,16]);
console.log('PASS merge comparison honors only approved exact story and character interval leading exception');
