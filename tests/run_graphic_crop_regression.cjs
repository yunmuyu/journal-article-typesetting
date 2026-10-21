const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const ctx=vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_layout_rules.jsxinc'),'utf8'),ctx);
assert.equal(ctx.JournalLayout.graphicIsCropped([0,0,54,70.75],[0,0,57.4,75.2]),true);
assert.equal(ctx.JournalLayout.graphicIsCropped([0,0,54,70.75],[-.01,-.01,54.01,70.76]),false);
assert.equal(ctx.JournalLayout.graphicIsCropped([10,20,64,90.75],[9.8,20,63.8,90.75]),true);
console.log('PASS full graphic bounds must stay inside the verified figure frame');
