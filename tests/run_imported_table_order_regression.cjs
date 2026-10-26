const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const ctx = vm.createContext({});
let source = fs.readFileSync(path.join(__dirname, '../2-导入_InDesign/journal_layout_rules.jsxinc'), 'utf8');
source = source.replace('sourceTableCharacterMatches:sourceTableCharacterMatches,', 'articleTables:articleTables,sourceTableCharacterMatches:sourceTableCharacterMatches,');
vm.runInContext(source, ctx);
// Given an ES3 engine that does not preserve ties during Array.sort.
vm.runInContext('var nativeSort=Array.prototype.sort; Array.prototype.sort=function(compare){return nativeSort.call(this,function(a,b){return compare(a,b)||-1;});};', ctx);
const story = {extractLabel:()=> 'body', tables:[{label:'', id:1},{label:'', id:2}]};
// When auditing imported tables without source labels.
const tables = ctx.JournalLayout.articleTables({stories:[story]});
// Then preserve their source story order even with an unstable sort implementation.
assert.deepEqual(Array.from(tables,t=>t.id), [1,2]);
story.tables = [{label:'source-table-2',id:2},{label:'source-table-1',id:1}];
assert.deepEqual(Array.from(ctx.JournalLayout.articleTables({stories:[story]}),t=>t.id), [1,2]);
console.log('PASS stable imported table order');

