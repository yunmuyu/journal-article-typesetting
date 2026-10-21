const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const ctx=vm.createContext({});vm.runInContext(fs.readFileSync('2-导入_InDesign/journal_layout_rules.jsxinc','utf8'),ctx);
for(const role of ['h1','h2']){assert.equal(ctx.JournalLayout.orphanScope(role,2),true);assert.equal(ctx.JournalLayout.orphanScope(role,1),false);}
for(const role of ['body','reference','bio'])assert.equal(ctx.JournalLayout.orphanScope(role,1),true);
for(const role of ['formula','english','caption'])assert.equal(ctx.JournalLayout.orphanScope(role,2),false);
console.log('PASS multiline headings share orphan repair and audit while single-line short titles remain legal');
ctx.Position={SUPERSCRIPT:1};
for(const name of ['一级标题','二级标题']){
 const text='智能监测技术概述\r',chars=[...text].map((contents,index)=>({contents,index,position:0,noBreak:false}));
 const line=(a,b)=>({contents:text.slice(a,b),insertionPoints:[{index:a}],characters:{everyItem:()=>({getElements:()=>chars.slice(a,b)})}});
 const p={index:0,contents:text,appliedParagraphStyle:{name},tables:[],lines:[line(0,7),line(7,text.length)]};
 const applied=[],story={id:1,extractLabel:()=> 'body',paragraphs:[p],tables:[],characters:{itemByRange(a,b){return {set noBreak(value){applied.push({a,b,value});for(let i=a;i<=b;i++)chars[i].noBreak=value;}}}}};
 const d={stories:[story],recompose(){p.lines=[line(0,6),line(6,text.length)];}};
 assert.equal(ctx.JournalLayout.repairOrphans(d),1);assert.deepEqual(applied,[{a:6,b:7,value:true}]);
 assert.equal(ctx.JournalLayout.orphanLine(p.lines[1]),false);assert.equal(p.contents,text);
}
console.log('PASS actual shared repair binds only the last two heading characters and preserves source text');
