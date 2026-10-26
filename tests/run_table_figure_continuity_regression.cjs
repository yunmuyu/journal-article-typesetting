const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');const ctx={};vm.createContext(ctx);vm.runInContext(fs.readFileSync('2-导入_InDesign/journal_prepreview_gate.jsxinc','utf8'),ctx);
const check=ctx.JournalPrepreviewGate.tableFigureInterruptions;
const tables=[{label:'source-table-1',parts:[{frameId:1,start:100,end:260},{frameId:2,start:1000100,end:1000140}]}];
assert.equal(check(tables,[{label:'图4',position:1000050}])[0].code,'TABLE_INTERRUPTED_BY_FIGURE');
assert.equal(check(tables,[{label:'图3',position:80},{label:'图4',position:1000200}]).length,0);
assert.equal(check([{label:'whole table',parts:[{start:100,end:200}]}],[{label:'outside',position:50}]).length,0);
const three=[{label:'table',parts:[...tables[0].parts,{frameId:3,start:2000100,end:2000200}]}];assert.equal(check(three,[{label:'图5',position:2000050}]).length,1);
console.log('PASS table continuation interrupted by a figure blocks; figures before/after whole table remain legal');
