const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const ctx=vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_article_assembly.jsxinc'),'utf8'),ctx);
const frames=[{id:'lower-right',geometricBounds:[225,110,265,195.5]},{id:'upper-right',geometricBounds:[26,110,114,195.5]},{id:'upper-left',geometricBounds:[30.2,17.5,114,103]},{id:'lower-left',geometricBounds:[225,17.5,265,103]}];
assert.deepEqual(ctx.JournalArticleAssembly.orderPanelFrames(frames).map(f=>f.id),['upper-left','upper-right','lower-left','lower-right']);
console.log('PASS panel columns keep horizontal order when continuation labels reserve unequal top space');
