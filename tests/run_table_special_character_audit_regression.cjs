const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path'),assert=require('node:assert/strict');
const context={};vm.createContext(context);vm.runInContext(fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_layout_rules.jsxinc'),'utf8'),context);
const glyph={contents:{toString:()=> 'DOUBLE_LEFT_QUOTE'},position:1,fontStyle:'Regular'};
const text={characters:{0:glyph,itemByRange(a,b){assert.equal(a,0);assert.equal(b,0);return {contents:'“'};}}};
const matches=context.JournalLayout.sourceTableCharacterMatches;
assert.equal(matches(text,0,'“',1,false),true);
assert.equal(matches(text,0,'”',1,false),false);
assert.equal(matches(text,0,'“',2,false),false);
glyph.fontStyle='Italic';assert.equal(matches(text,0,'“',1,false),false);assert.equal(matches(text,0,'“',1,true),true);
const citations='[1][2][3][4][13]';
const citationChars=Array.from(citations,c=>({contents:c,position:'superscript',fontStyle:'Regular'}));
const citationText={characters:{itemByRange(a,b){return {contents:citations.slice(a,b+1)};}}};
for(let i=0;i<citationChars.length;i++)citationText.characters[i]=citationChars[i];
for(let i=0;i<citations.length;i++)assert.equal(matches(citationText,i,citations[i],'superscript',false),true);
citationChars[citations.indexOf('13')+1].position='normal';
assert.equal(matches(citationText,citations.indexOf('13')+1,'3','superscript',false),false,
  'a dropped superscript in a multi-digit table citation must fail character-level audit');
console.log('PASS table character position audit catches a dropped superscript citation');
