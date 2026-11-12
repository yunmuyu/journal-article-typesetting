const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path'),assert=require('node:assert/strict');
const context={};vm.createContext(context);vm.runInContext(fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_layout_rules.jsxinc'),'utf8'),context);
const glyph={contents:{toString:()=> 'DOUBLE_LEFT_QUOTE'},position:1,fontStyle:'Regular'};
const text={characters:{0:glyph,itemByRange(a,b){assert.equal(a,0);assert.equal(b,0);return {contents:'“'};}}};
const matches=context.JournalLayout.sourceTableCharacterMatches;
const project=context.JournalLayout.projectTableRuns;
const runs=[
  {tableIndex:0,rowIndex:0,cellIndex:0,start:0,text:'A⟦EQ-'},
  {tableIndex:0,rowIndex:0,cellIndex:0,start:5,text:'001⟧B⟦EQ-002⟧'},
  {tableIndex:0,rowIndex:0,cellIndex:0,start:18,text:'²',italic:true,position:'superscript'},
  {tableIndex:0,rowIndex:0,cellIndex:1,start:0,text:'C'}
];
const projected=project(runs);
assert.deepEqual(Array.from(projected.runs,r=>[r.cellIndex,r.start,r.text]),[[0,0,'A'],[0,2,'B'],[0,4,'²'],[1,0,'C']]);
assert.deepEqual(Array.from(projected.anchors,r=>[r.cellIndex,r.start,r.number]),[[0,1,1],[0,3,2]]);
assert.equal(projected.runs[2].italic,true);
assert.equal(projected.runs[2].position,'superscript');
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
