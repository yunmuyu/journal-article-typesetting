const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const {test}=require('node:test');
function list(a){a[-1]=a.at(-1);return a;}
function fixture(tracking){
 let value=0,writes=0;
 const chars=list(Array.from({length:12},(_,index)=>({index})));
 const p={contents:'abcdefghijk\r',characters:chars,insertionPoints:[{index:0}],startParagraph:0};
 Object.defineProperty(p,'tracking',{get:()=>value,set:v=>{value=v;writes++;}});
 p.textStyleRanges={everyItem:()=>({getElements:()=>[{characters:chars,get tracking(){return value;}}]})};
 chars.forEach(c=>c.paragraphs=[p]);
 chars.itemByRange=()=>({set tracking(v){value=v;writes++;}});
 const page={id:20};
 class TextFrame{constructor(id){this.id=id;this.parentPage=page;this.geometricBounds=[26,0,265,85.5];}}
 const frames=[new TextFrame(10),new TextFrame(11)];
 function line(a,b){return {insertionPoints:list([{index:a},{index:b}])};}
 const body={id:2,contents:p.contents,paragraphs:[p],characters:chars,textContainers:frames,overflows:false,extractLabel:()=> 'body'};
 const d={id:1,stories:[body],allPageItems:frames,pages:list([page]),recompose(){
  p.lines=value<0?list([line(0,12)]):value>0?list([line(0,4),line(4,8),line(8,12)]):list([line(0,6),line(6,12)]);
  frames[0].lines=p.lines;frames[1].lines=[];
 }};
 d.recompose();
 const ctx=vm.createContext({JournalLayoutMeasurement:{
  flowSignature:()=> 'flow:'+value,trackingContext:()=> 'tracking:'+value
 },JournalLayout:{orphanLine:()=>false,protectedTokens:()=>[]}});
 vm.runInContext(fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_reflow.jsxinc'),'utf8'),ctx);
 const plan={schemaVersion:1,documentId:1,storyId:2,flowSignature:'flow:0',tracking:[
  {start:0,text:p.contents,tracking,context:'tracking:0',expectedLineCount:tracking<0?1:3}
 ],leadingCompression:[],lastPageBalance:{frameIds:[10,11]}};
 return {api:ctx.JournalReflow,d,plan,value:()=>value,writes:()=>writes};
}
for(const value of [-7.5,2.5])test(`same reflow executor applies tracking ${value}`,()=>{
 const f=fixture(value),result=f.api.apply(f.d,f.plan,()=>[]);
 assert.equal(result.tracking,1);assert.equal(f.value(),value);
});
test('stale measured flow is rejected without document writes',()=>{
 const f=fixture(-7.5);f.plan.flowSignature='old';
 assert.throws(()=>f.api.apply(f.d,f.plan,()=>[]),/MEASUREMENT_STALE/);assert.equal(f.writes(),0);
});
test('changed character formatting is rejected without document writes',()=>{
 const f=fixture(-7.5);f.plan.tracking[0].context='old';
 assert.throws(()=>f.api.apply(f.d,f.plan,()=>[]),/CONTEXT_CHANGED/);assert.equal(f.writes(),0);
});
test('outcome mismatch rolls back tracking rather than silently continuing',()=>{
 const f=fixture(-7.5);f.plan.tracking[0].expectedLineCount=2;
 assert.throws(()=>f.api.apply(f.d,f.plan,()=>[]),/OUTCOME_CHANGED/);assert.equal(f.value(),0);
});
