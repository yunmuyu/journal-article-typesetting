const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const root=path.resolve(__dirname,'../2-导入_InDesign');
const ctx=vm.createContext({JournalLayout:{last:()=>100,visibleBottom:()=>100}});
for(const name of ['journal_layout_measurement.jsxinc','journal_bottom_plan.jsxinc','journal_reflow.jsxinc'])vm.runInContext(fs.readFileSync(path.join(root,name),'utf8'),ctx);
function list(a){a[-1]=a.at(-1);return a;}
const text='作者简介：朱某，工程师，研究方向：数据服务。\r',p={contents:text,appliedParagraphStyle:{name:'作者简介'},tables:[],insertionPoints:list([{index:0},{index:text.length}]),startParagraph:0};
const chars=list(Array.from(text,(contents,index)=>({index,contents,pointSize:index<5?12:9,leading:index<5?16:13,paragraphs:[p],getElements(){return [this]}})));
function range(a,b){const selected=chars.slice(a,b+1);return {contents:text.slice(a,b+1),characters:list(selected),getElements:()=>selected,get leading(){return selected[0].leading},set leading(v){selected.forEach(c=>c.leading=v)},textStyleRanges:{everyItem:()=>({getElements:()=>[chars.slice(a,Math.min(b+1,5)),chars.slice(Math.max(a,5),b+1)].filter(x=>x.length).map(x=>({characters:list(x),pointSize:x[0].pointSize,leading:x[0].leading}))})}}}
chars.itemByRange=range;p.characters=chars;
const page={id:20};class TextFrame{constructor(id){this.id=id;this.parentPage=page;this.geometricBounds=[26,0,265,85.5];}}
const frames=[new TextFrame(10),new TextFrame(11)];
function line(a,b){return {contents:text.slice(a,b),characters:list(chars.slice(a,b)),paragraphs:[p],baseline:30,ascent:3,descent:.5,horizontalOffset:0,endHorizontalOffset:10,insertionPoints:list([{index:a,parentTextFrames:[frames[0]]},{index:b,parentTextFrames:[frames[0]]}])}}
frames[0].lines=[line(0,8),line(8,16),line(16,text.length)];frames[1].lines=[];
const body={id:2,contents:text,paragraphs:[p],characters:chars,textContainers:frames,tables:[],overflows:false,extractLabel:()=> 'body'};
const d={id:1,stories:[body],allPageItems:frames,pages:list([page]),recompose(){}};
const M=ctx.JournalLayoutMeasurement,first=M.lineRecord(frames[0].lines[0]),second=M.lineRecord(frames[0].lines[1]);
assert.equal(first.leading,13,'schema retains last-character leading');assert.equal(first.adjustableLeading,false);assert.equal(second.adjustableLeading,true);
const state=M.frameState(body)[0];assert.ok(Math.abs(state.leadingDownMm-.4*25.4/72)<1e-10);assert.ok(Math.abs(state.leadingUpMm-.4*25.4/72)<1e-10);
const {groups}=require('../2-导入_InDesign/journal_bottom_measurement_request.cjs');
const records=frames[0].lines.map(l=>M.lineRecord(l));assert.deepEqual(groups({id:10,lines:records}).map(g=>g.target.startIndex),[8]);
ctx.JournalBottomPlan.apply(d,{status:'ready',blankSpaceAllowed:false,columns:[{adjustments:[{kind:'leading',role:'reference',toPt:13.366424,target:{storyRole:'body',startIndex:0,endIndex:15}}]}]});
assert.ok(chars.slice(0,5).every(c=>c.leading===16));assert.ok(chars.slice(5,16).every(c=>c.leading===13.366424));assert.equal(chars[16].leading,13);
chars.forEach((c,i)=>c.leading=i<5?16:13);
const plan={schemaVersion:1,documentId:1,storyId:2,tracking:[],leadingCompression:[{start:0,end:text.length,text,role:'bio',leading:12.8}],lastPageBalance:{frameIds:[10,11]}};
ctx.JournalReflow.apply(d,plan,()=>[]);assert.ok(chars.slice(0,5).every(c=>c.leading===16));assert.ok(chars.slice(5).every(c=>c.leading===12.8));assert.equal(body.contents,text);
chars.forEach((c,i)=>c.leading=i<5?16:13);
assert.throws(()=>ctx.JournalReflow.apply(d,plan,()=>{throw Error('synthetic failure')}),/synthetic failure/);assert.ok(chars.slice(0,5).every(c=>c.leading===16));assert.ok(chars.slice(5).every(c=>c.leading===13));
const {build}=require('../2-导入_InDesign/journal_reflow_plan.cjs');
const mk=(start)=>({start,end:start+10,paragraphStart:0,baseline:30,leading:13,ascent:3,role:'bio',text:'ten letters',adjustableLeading:true});
const measured={schemaVersion:1,documentId:1,storyId:2,flowSignature:'synthetic',trackingProbes:[],paragraphs:[],frames:[{id:10,index:0,pageIndex:0,bounds:[26,0,265,85.5],endpoint:[0,20],bottomMm:260,targetBottomMm:264.3445,lines:[mk(0),{...mk(10),adjustableLeading:false}]},{id:11,index:1,pageIndex:0,bounds:[26,92,265,178],endpoint:[20,40],lines:[mk(20),mk(30)]}]};
assert.equal(build(measured,{columns:[{id:'10',status:'blocked'}],deferred:[]}).leadingCompression.length,0,'fixed label contributes no false compression capacity');
measured.frames[0].lines[1].adjustableLeading=true;assert.equal(build(measured,{columns:[{id:'10',status:'blocked'}],deferred:[]}).leadingCompression.length,2);
console.log('PASS mixed biography label remains 12pt/16pt; measurement, bottom and reflow exclude fixed label capacity while adjusting only 9pt text, with rollback');
