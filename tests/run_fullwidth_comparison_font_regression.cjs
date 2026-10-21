const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const modulePath=path.resolve(__dirname,'../2-导入_InDesign/journal_layout_rules.jsxinc');
const source=fs.readFileSync(modulePath,'utf8');const context={FontStatus:{INSTALLED:1},app:{fonts:{itemByName(name){return {name,isValid:true,status:1}}}}};vm.createContext(context);vm.runInContext(source,context);
assert.equal(context.JournalLayout.specialGlyphFont('＞'),'黑体');assert.equal(context.JournalLayout.specialGlyphFont('＜'),'黑体');
const symbol={contents:'＞',appliedFont:{name:'Times New Roman'},pointSize:9,fontStyle:'Regular'};Object.defineProperty(symbol,'properties',{set(value){Object.assign(this,value)}});
const ordinary={contents:'A',appliedFont:{name:'Times New Roman'},pointSize:10.5,fontStyle:'Italic'};
context.JournalLayout.applySpecialGlyphs({characters:{everyItem(){return {getElements(){return [symbol,ordinary]}}}}});
assert.equal(symbol.appliedFont.name,'黑体');assert.equal(symbol.contents,'＞');assert.equal(symbol.pointSize,9);assert.equal(ordinary.fontStyle,'Italic');
console.log('PASS fullwidth comparison fallback is local and preserves content and size');

assert.equal(context.JournalLayout.specialGlyphRangeFontAllowed('＞＜','黑体'),true);
assert.equal(context.JournalLayout.specialGlyphRangeFontAllowed('＞9','黑体'),false);
assert.equal(context.JournalLayout.specialGlyphRangeFontAllowed('普通文字','黑体'),false);
assert.equal(context.JournalLayout.specialGlyphRangeFontAllowed('＞','Times New Roman'),false);
