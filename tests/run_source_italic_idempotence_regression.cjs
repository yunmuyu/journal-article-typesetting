const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const italic={name:'Times New Roman\tItalic',fontFamily:'Times New Roman',postscriptName:'TimesNewRomanPS-ItalicMT',status:1};
const regular={name:'Times New Roman\tRegular',fontFamily:'Times New Roman',postscriptName:'TimesNewRomanPSMT',status:1};
const c=vm.createContext({Position:{NORMAL:0},FontStatus:{INSTALLED:1},app:{fonts:{everyItem:()=>({getElements:()=>[italic,regular]})}}});
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

function legacyCharacter(contents,face,resolveFamily=true){
    // The native host can report installed and the correct PS name for this stale alias.
    let font={...(face==='Italic'?italic:regular),name:'Times New Roman (OTF)\t'+face+face};
    return {
        contents,position:0,fontStyle:face,
        get appliedFont(){return font;},
        set properties(values){
            this.fontStyle=values.fontStyle;
            if(resolveFamily&&values.appliedFont==='Times New Roman')font=values.fontStyle==='Italic'?italic:regular;
        }
    };
}
const legacy=[legacyCharacter('P','Italic'),legacyCharacter('Q','Regular')];
const legacyDoc={stories:[{paragraphs:[{...paragraph,contents:'PQ',characters:legacy}],extractLabel:()=> 'body'}]};
const legacySource={sourceTextFormatting:[{role:'body',text:'PQ',runs:[{start:0,end:1,italic:true}]}]};
assert.equal(c.JournalLayout.sourceTextFormatting(legacyDoc,legacySource,false).filter(x=>x.includes('SOURCE_TEXT_TIMES_FONT')).length,2);
assert.deepEqual(Array.from(c.JournalLayout.sourceTextFormatting(legacyDoc,legacySource,true)),[]);
assert.equal(legacy[0].appliedFont,italic);
assert.equal(legacy[1].appliedFont,regular);
legacy[0]=legacyCharacter('P','Italic',false);
assert.equal(c.JournalLayout.sourceTextFormatting(legacyDoc,legacySource,true).filter(x=>x.includes('SOURCE_TEXT_TIMES_FONT')).length,1);
console.log('PASS source formatting corrects legacy italic and regular resources and rejects a failed native remap');

const digit=legacyCharacter('7','Regular');
const digitParagraph={...paragraph,contents:'7',characters:{everyItem:()=>({getElements:()=>[digit]})}};
c.JournalLayout.normalizeDigitFonts({stories:[{paragraphs:[digitParagraph],extractLabel:()=> 'body'}]});
assert.equal(digit.appliedFont,regular);
digitParagraph.characters.everyItem=()=>({getElements:()=>[legacyCharacter('7','Regular',false)]});
assert.throws(()=>c.JournalLayout.normalizeDigitFonts({stories:[{paragraphs:[digitParagraph],extractLabel:()=> 'body'}]}),/DIGIT_FONT_ASSIGNMENT.*Times New Roman \(OTF\)/);

const cellCharacter=legacyCharacter('x','Italic');
const cellText={characters:{0:cellCharacter,itemByRange(){return this[0];}}};
const table={label:'source-table-1',rows:[{cells:[{texts:[cellText]}]}]};
const tableDoc={stories:[{tables:[table],extractLabel:()=> 'body'}]};
const tableConfig={tableTextRuns:[{tableIndex:0,rowIndex:0,cellIndex:0,start:0,text:'x',italic:true}]};
c.JournalLayout.applySourceTableFormatting(tableDoc,tableConfig);
assert.equal(cellCharacter.appliedFont,italic);
cellText.characters[0]=legacyCharacter('x','Italic',false);
assert.throws(()=>c.JournalLayout.applySourceTableFormatting(tableDoc,tableConfig),/SOURCE_TABLE_FONT_ALIAS.*Times New Roman \(OTF\)/);
console.log('PASS native digit and source table assignments use the canonical family and preserve the requested face');
