const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const ctx=vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_layout_rules.jsxinc'),'utf8'),ctx);
const digit={contents:'7',appliedFont:{name:'Synthetic Composite\tRegular'}};
const entry={isValid:true,appliedFont:'Times New Roman'};
const composite={isValid:true,compositeFontEntries:{length:5,itemByName:()=>entry}};
const doc={compositeFonts:{itemByName:()=>composite}};
// Given a standard composite with a verified numeric mapping.
// When auditing a digit, Then use the effective mapped font.
assert.equal(ctx.JournalLayout.digitFontMatches(doc,digit),true);
entry.appliedFont='Wrong Font';
assert.equal(ctx.JournalLayout.digitFontMatches(doc,digit),false);
entry.appliedFont='Times New Roman';composite.compositeFontEntries.length=6;
assert.equal(ctx.JournalLayout.digitFontMatches(doc,digit),false); // custom overrides need separate evidence
composite.isValid=false;
assert.equal(ctx.JournalLayout.digitFontMatches(doc,digit),false);
digit.appliedFont.name='Times New Roman\tRegular';
assert.equal(ctx.JournalLayout.digitFontMatches(doc,digit),true);
digit.appliedFont.name='Unapproved Font\tRegular';
assert.equal(ctx.JournalLayout.digitFontMatches(doc,digit),false);
console.log('PASS effective composite digit font and negative mappings');
