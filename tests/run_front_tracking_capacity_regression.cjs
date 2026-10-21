const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const ctx=vm.createContext({});vm.runInContext(fs.readFileSync('2-导入_InDesign/journal_layout_rules.jsxinc','utf8'),ctx);
assert.equal(typeof ctx.JournalLayout.lineChangeTrackingChoices,'function');
const observed=[];const choices=ctx.JournalLayout.lineChangeTrackingChoices(t=>{observed.push(t);return {lineCount:t>=3?11:t<=-8?9:10,legal:t<0||t>=3.5};},0,10);
assert.equal(choices.length,2);assert.ok(choices[0].tracking>=3.5&&choices[0].tracking<3.7);assert.ok(choices[1].tracking<=-8);
assert.ok(observed.every(t=>Math.abs(t)<=20));assert.equal(choices[0].lineDelta,1);assert.equal(choices[1].lineDelta,-1);
assert.equal(ctx.JournalLayout.lineChangeTrackingChoices(()=>({lineCount:10,legal:true}),0,10).length,0);
console.log('PASS measured front tracking searches both directions, rejects illegal threshold wraps and respects absolute 20 limit');
