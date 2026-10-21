const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),c=vm.createContext({});vm.runInContext(fs.readFileSync('2-导入_InDesign/journal_layout_rules.jsxinc','utf8'),c);
const rows=['issue','profile',[[1,'text','','',[]],[3,'missing glyph','19','detail',[]],[3,'overset','336','detail',[]]]],names=Array.from({length:350},(_,i)=>String(i+1));
const p=c.JournalLayout.partitionPreflight(rows,names,[335,340]);assert.equal(p.scoped.length,1);assert.equal(p.outside.length,1);assert.equal(p.unknown.length,0);
assert.equal(c.JournalLayout.partitionPreflight(['i','p',[[3,'unknown','','',[]]]],names,[335,340]).unknown.length,1);
names[340]='19';assert.equal(c.JournalLayout.partitionPreflight(rows,names,[335,340]).unknown.length,1);
assert.equal(c.JournalLayout.partitionPreflight(rows,names,null).scoped.length,2);
console.log('PASS complete preflight evidence retained; only uniquely located outside-article issues classified separately');
