const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const ctx=vm.createContext({});vm.runInContext(fs.readFileSync('2-导入_InDesign/journal_article_assembly.jsxinc','utf8'),ctx);
const geometry=ctx.JournalArticleAssembly.panelRows;
assert.deepEqual(JSON.parse(JSON.stringify(geometry([98,84],1,4))),{offsets:[0,102],height:186});
assert.deepEqual(JSON.parse(JSON.stringify(geometry([98,84],2,4))),{offsets:[0,0],height:98});
assert.deepEqual(JSON.parse(JSON.stringify(geometry([98],1,4))),{offsets:[0],height:98});
console.log('PASS page-top panels preserve separate rows and existing single-row height');
