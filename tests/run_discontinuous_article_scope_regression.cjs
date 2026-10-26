const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const context = vm.createContext({});
let source = fs.readFileSync(path.join(__dirname, '../2-导入_InDesign/journal_layout_rules.jsxinc'), 'utf8');
// Exercise the existing private view builder before its public export is added.
source = source.replace('return {sourceTableCharacterMatches:', 'return {auditView:auditView,sourceTableCharacterMatches:');
vm.runInContext(source, context);
const pages = Array.from({length:7}, (_, i) => ({documentOffset:i, name:String(i + 1), parent:{}}));
const story = {id:1, isValid:true, paragraphs:[], textContainers:[{parentPage:pages[1]}, {parentPage:pages[5]}]};
for (const frame of story.textContainers) Object.assign(frame, {lines:[{contents:'synthetic body'}], tables:[], geometricBounds:[0,0,100,80]});
const doc = {name:'synthetic_QA.indd', pages, stories:{itemByID:()=>story},
  allGraphics:[], allPageItems:pages.map(p=>({parentPage:p})), allParagraphStyles:[], recompose(){}};
// Given: the same article continues beyond intervening pages belonging to others.
const config = {bindings:[{id:1}], articlePageIndices:[1,5]};
// When
const view = context.JournalLayout.auditView(doc, config);
// Then: preserve physical offsets, inspect only the explicitly declared pages.
assert.deepEqual(Array.from(view.pages, p=>p.documentOffset), [1,5]);
assert.equal(view.allPageItems.length, 2);
assert.throws(()=>context.JournalLayout.run(doc, config, true), /FULL_TARGET_CHECK_ONLY/);
for (const indices of [[], [1,1], [5,1], [-1,5], [1,7], [1,5.5], [1]]) {
  assert.throws(()=>context.JournalLayout.auditView(doc, {...config, articlePageIndices:indices}), /ARTICLE_PAGE/);
}
assert.throws(()=>context.JournalLayout.auditView(doc, {...config, articlePageRange:[1,5]}), /ARTICLE_PAGE/);
const rows = ['issue','profile',[[3,'overset','3','',[]],[3,'overset','6','',[]]]];
const partition = context.JournalLayout.partitionPreflight(rows, pages.map(p=>p.name), null, [1,5]);
assert.equal(partition.scoped.length, 1);
assert.equal(partition.outside.length, 1);
// Actual empty-page gate: skipped pages must disappear, declared blank pages must not.
let gate = fs.readFileSync(path.join(__dirname, '../2-导入_InDesign/journal_prepreview_gate.jsxinc'), 'utf8');
gate = gate.replace('return {audit:audit}', 'return {audit:audit,auditEmptyRegions:auditEmptyRegions}');
vm.runInContext(gate, context);
const ctx = {body:story, visibleBottom:()=>100};
assert.equal(context.JournalPrepreviewGate.auditEmptyRegions(view, {}, ctx).filter(e=>e.code==='EMPTY_ARTICLE_PAGE').length, 0);
const declaredBlank = context.JournalLayout.auditView(doc, {...config, articlePageIndices:[1,2,5]});
assert.equal(context.JournalPrepreviewGate.auditEmptyRegions(declaredBlank, {}, ctx).filter(e=>e.code==='EMPTY_ARTICLE_PAGE').length, 1);
console.log('PASS discontinuous article page scope and preflight partition');
