const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const italic={name:'Times New Roman\tItalic',fontFamily:'Times New Roman',postscriptName:'TimesNewRomanPS-ItalicMT',status:1};
const c=vm.createContext({Position:{NORMAL:0},FontStatus:{INSTALLED:1},app:{fonts:{everyItem:()=>({getElements:()=>[italic]})}}});
vm.runInContext(fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_layout_rules.jsxinc'),'utf8'),c);
// Given: native text already has the requested face; reassigning it can fail in a recycled document.
const character={contents:'P',position:0,fontStyle:'Italic',get appliedFont(){return italic;},set appliedFont(value){throw Error('NATIVE_REDUNDANT_FONT_ASSIGNMENT');}};
const paragraph={contents:'P',characters:[character],appliedParagraphStyle:{name:'正文_wrd_1'}};
const doc={stories:[{paragraphs:[paragraph],extractLabel:()=> 'body'}]};
// When / Then: formatting is idempotent and still validates the source italic contract.
assert.equal(c.JournalLayout.sourceTextFormatting(doc,{sourceTextFormatting:[{role:'body',text:'P',runs:[{start:0,end:1,italic:true}]}]},true).length,0);
assert.equal(character.fontStyle,'Italic');
const regularCharacter={contents:'P',position:0,fontStyle:'Regular',appliedFont:{name:'现 宋体-1'}};
const repeated={stories:[{paragraphs:[paragraph,{...paragraph,characters:[regularCharacter]}],extractLabel:()=> 'body'}]};
const source={sourceTextFormatting:[{role:'body',text:'P',runs:[{start:0,end:1,italic:true}]},{role:'body',text:'P',runs:[]}]};
assert.equal(c.JournalLayout.sourceTextFormatting(repeated,source,false).length,0);
assert.equal(c.JournalLayout.sourceTextFormatting(doc,source,false).length,2);
const punctuation={contents:'、',position:0,fontStyle:'Regular',appliedFont:{name:'现 宋体-1'}};
const equals={contents:'=',position:0,fontStyle:'Italic',get appliedFont(){return {name:'Symbol\tItalic'};},
    set properties(value){throw Error('NATIVE_REDUNDANT_OPERATOR_ASSIGNMENT');}};
const notation={stories:[{paragraphs:[{...paragraph,contents:'P、=',characters:[character,punctuation,equals]}],
    extractLabel:()=> 'body'}]};
assert.equal(c.JournalLayout.sourceTextFormatting(notation,
    {sourceTextFormatting:[{role:'body',text:'P、=',runs:[{start:0,end:3,italic:true}]}]},true).length,0);
assert.equal(punctuation.fontStyle,'Regular');
console.log('PASS matching source italic is validated without redundant native face assignment');
