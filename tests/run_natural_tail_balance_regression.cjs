const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const ctx=vm.createContext({VerticalJustification:{TOP_ALIGN:1}});vm.runInContext(fs.readFileSync('2-导入_InDesign/journal_layout_rules.jsxinc','utf8'),ctx);
const page={id:7,documentOffset:6},tail={id:99,documentOffset:98};const pages=[page,tail];pages[-1]=tail;
const unrelated={extractLabel(){throw Error('UNRELATED_STORY_READ');}};
const body={paragraphs:[],textContainers:[],tables:[],overflows:false,textStyleRanges:{everyItem:()=>({getElements:()=>[]})},extractLabel:()=> 'body'};const d={pages,stories:[unrelated],recompose(){}};
assert.equal(ctx.JournalLayout.balanceLastPage(d,body),false);
console.log('PASS merged-issue body scope avoids unrelated stories and document-last-page assumptions');
const emptyTables={everyItem:()=>({getElements:()=>[]})};
function frame(id){return {id,parentPage:page,geometricBounds:[26,id===1?14.5:107,265,id===1?100:192.5],textFramePreferences:{textColumnCount:1},insertionPoints:[{index:0}],tables:emptyTables,allGraphics:[],lines:[]};}
const left=frame(1),right=frame(2),tailBody={paragraphs:[],tables:[],contents:'unchanged original text',overflows:false,textContainers:[left,right]};
const model={pages,recompose(){const capacity=Math.max(0,Math.floor((left.geometricBounds[2]-26)/5));const leftCount=Math.min(60,capacity),rightCount=60-leftCount;left.lines=Array.from({length:leftCount},(_,i)=>({baseline:26+(i+1)*5,insertionPoints:[{parentTextFrames:[left]}]}));right.lines=Array.from({length:rightCount},(_,i)=>({baseline:26+(i+1)*5,insertionPoints:[{parentTextFrames:[right]}]}));tailBody.overflows=rightCount>Math.floor((right.geometricBounds[2]-26)/5);}};
model.recompose();assert.equal(ctx.JournalLayout.balanceLastPage(model,tailBody),true);assert.equal(tailBody.overflows,false);assert.equal(left.lines.length,30);assert.equal(right.lines.length,30);assert.equal(tailBody.contents,'unchanged original text');assert(Math.abs(left.geometricBounds[2]-right.geometricBounds[2])<.001);
console.log('PASS ordinary final-page geometry balances flow in the middle of an issue without changing text');