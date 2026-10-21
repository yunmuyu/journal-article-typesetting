const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const ctx=vm.createContext({PageSideOptions:{LEFT_HAND:'left'}});vm.runInContext(fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_article_assembly.jsxinc'),'utf8'),ctx);
const A=ctx.JournalArticleAssembly;
function list(a){a[-1]=a.at(-1);return a;}
function fixture(text,mode='normal'){
 let nextId=1,additions=0,recomposes=0;
 const body={contents:text,overflows:true,textContainers:[]};
 const pages=list([]);
 function frame(page,bounds){const f={id:nextId++,parentPage:page,geometricBounds:bounds,lines:[]};Object.defineProperty(f,'nextTextFrame',{set(next){if(!body.textContainers.includes(next))body.textContainers.push(next)}});return f;}
 function page(){const p={id:nextId++,side:'left',appliedMaster:'source-master',textFrames:[]};p.textFrames.add=spec=>{const f=frame(p,spec.geometricBounds);p.textFrames.push(f);return f};p.remove=()=>{pages.splice(pages.indexOf(p),1);pages[-1]=pages.at(-1);body.textContainers=body.textContainers.filter(f=>f.parentPage!==p)};return p;}
 for(let i=0;i<8;i++){const p=page();pages.push(p);for(let c=0;c<2;c++)body.textContainers.push(p.textFrames.add({geometricBounds:[26,14.5+c*92.5,265,100+c*92.5]}));}pages[-1]=pages.at(-1);
 pages.add=()=>{additions++;const p=page();pages.push(p);pages[-1]=p;return p};
 const d={pages,recompose(){recomposes++;let end=0;for(let i=0;i<body.textContainers.length;i++){const f=body.textContainers[i],start=end;if(i<16||mode==='normal')end=Math.min(text.length,end+1100);f.lines=(i>=16&&mode==='blank'||start===text.length)?[]:[{contents:text.slice(start,end),insertionPoints:list([{index:start,parentTextFrames:[f]},{index:end,parentTextFrames:[f]}])}];}body.overflows=end<text.length;}};
 d.recompose();
 const job={allowPageGrowth:true,templateContract:{geometry:{bodyTopMm:26,bodyBottomMm:265,columnWidthMm:85.5,columnGapMm:7,spreadWidthMm:178,leftPageLeftMm:14.5,rightPageLeftMm:17.5}}};
 return {d,body,job,additions:()=>additions,recomposes:()=>recomposes};
}
let text='文'.repeat(20622)+'表'.repeat(297),source='synthetic 20,622 body + 297 table characters';
if(process.argv[2]){const logical=JSON.parse(fs.readFileSync(process.argv[2],'utf8').replace(/^\uFEFF/,''));text=logical.blocks.map(b=>b.text||'').join('\r');source='actual extracted source logical text '+text.length+' UTF-16 characters';}
const f=fixture(text),original=f.body.contents;const added=A.growBodyPages(f.d,f.body,f.job);
assert.equal(added,Math.ceil(text.length/2200)-8);assert.equal(f.d.pages.length,8+added);assert.equal(f.body.overflows,false);assert.equal(f.body.contents,original);assert.equal(A.lastVisibleIndex(f.body),text.length);
for(const page of f.d.pages.slice(8)){assert.equal(page.textFrames.length,2);assert.equal(page.appliedMaster,'source-master');assert.deepEqual(page.textFrames.map(x=>Array.from(x.geometricBounds)),[[26,14.5,265,100],[26,107,265,192.5]]);}
const strict=fixture('x'.repeat(20919));delete strict.job.allowPageGrowth;assert.equal(A.growBodyPages(strict.d,strict.body,strict.job),0);assert.equal(strict.body.overflows,true);assert.equal(strict.additions(),0);
for(const mode of ['blank','stalled']){const blocked=fixture('x'.repeat(20919),mode),before=blocked.body.contents;assert.throws(()=>A.growBodyPages(blocked.d,blocked.body,blocked.job),/BODY_UNBREAKABLE_FLOW/);assert.equal(blocked.additions(),1);assert.equal(blocked.d.pages.length,8);assert.equal(blocked.body.contents,before);}
const moduleText=fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_article_assembly.jsxinc'),'utf8');assert.equal((moduleText.match(/result.addedPages=growBodyPages\(d,body,job\)/g)||[]).length,2,'run and normalize share the same guarded growth');
console.log(`PASS ${source}; initial 8 pages grew by ${added} complete double-column pages, exact source preserved, legacy strictness and first-page no-progress stop`);
