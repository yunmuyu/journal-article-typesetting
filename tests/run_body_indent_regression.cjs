const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const ctx=vm.createContext({Justification:{RIGHT_ALIGN:2,LEFT_JUSTIFIED:1},SpecialCharacters:{ELLIPSIS_CHARACTER:9}});
vm.runInContext(fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_layout_rules.jsxinc'),'utf8'),ctx);
function paragraph(style,indent,text='合成段落\r'){
 const chars=Object.assign([],{everyItem:()=>({getElements:()=>[]})});
 return {contents:text,appliedParagraphStyle:{name:style,firstLineIndent:22*25.4/72},firstLineIndent:indent,
 justification:0,characters:chars,textStyleRanges:{everyItem:()=>({getElements:()=>[]})},tables:[],allPageItems:[],lines:[]};
}
const body=paragraph('正文_wrd_1',0),good=paragraph('正文',22*25.4/72),custom=paragraph('期刊正文_模板',24*25.4/72);
custom.appliedParagraphStyle.firstLineIndent=24*25.4/72;
const protectedParagraphs=['一级标题','二级标题','图注/表名','公式'].map(s=>paragraph(s,0,s==='公式'?'\r':s+'\r'));
const anchor=paragraph('正文',0,'\u0016\r');anchor.tables=[{}];
const story={extractLabel:()=> 'body',paragraphs:[body,good,custom,...protectedParagraphs],tables:[]};
const d={stories:[story],allParagraphStyles:[],allPageItems:[],recompose(){}};
ctx.JournalLayout.applyTypography(d,{});
assert.equal(body.firstLineIndent,22*25.4/72,'left-aligned body with local zero override recovers the template indent');
assert.equal(good.firstLineIndent,22*25.4/72);
assert.equal(custom.firstLineIndent,24*25.4/72,'do not hardcode a different approved template indent');
assert.ok(protectedParagraphs.every(p=>p.firstLineIndent===0),'headings, captions and equations remain unindented');
story.paragraphs.push(anchor);
assert.equal(ctx.JournalLayout.bodyIndentation(d,false).length,0,'table anchors are not prose');
body.firstLineIndent=0;
assert.equal(ctx.JournalLayout.bodyIndentation(d,false).length,1,'local overrides are detected without writes');
assert.equal(body.firstLineIndent,0);
ctx.JournalLayout.bodyIndentation(d,true);ctx.JournalLayout.bodyIndentation(d,true);
assert.equal(body.firstLineIndent,22*25.4/72);assert.equal(anchor.firstLineIndent,0);
console.log('PASS body local override repair, template indent preservation, non-prose protection and idempotency');
