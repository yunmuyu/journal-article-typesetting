const assert=require('node:assert/strict');
const {derive}=require('../2-导入_InDesign/complete_assembly_check_config.cjs');
const panel={numbers:[2],columns:1,pageIndex:1,pageTop:true};
const assembly={outputPath:'article_QA.indd',bindings:[],panels:[panel]};
const snapshot={stories:[{role:'body',frames:[{page:1,bounds:[90,14.5,265,100]},{page:1,bounds:[90,107,265,192.5]}]}]};
const result=derive({},assembly,snapshot);
assert.deepEqual(result.figurePanels,[panel]);
console.log('PASS single-figure wide panels retain their explicit centering and page contracts');
