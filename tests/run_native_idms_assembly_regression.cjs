const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const modulePath=path.resolve(__dirname,'../2-导入_InDesign/journal_article_assembly.jsxinc');
const ctx={File:p=>({exists:p!=='missing.idms',path:p}),AnchorPosition:{INLINE_POSITION:'inline'}};
vm.createContext(ctx);vm.runInContext(fs.readFileSync(modulePath,'utf8'),ctx);const A=ctx.JournalArticleAssembly;
assert.deepEqual(Array.from(A.formulaMarkers('甲⟦EQ-001⟧乙⟦EQ-013⟧'),x=>[x.number,x.start]),[[1,1],[13,10]]);
assert.throws(()=>A.validateFormulaMarkers([{text:'甲⟦EQ-001⟧乙'},{text:'⟦EQ-001⟧'}]),/FORMULA_MARKER_DUPLICATE/);
A.validateFormulaMarkers([{text:'⟦EQ-001⟧'},{text:'甲⟦EQ-002⟧乙'}]);
assert.equal(A.printedFormulaNumber({mode:'native-idms'},1,'（7）'),null,'new cache mode never invents source numbering');
assert.equal(A.printedFormulaNumber({mode:'native-idms',displayNumbers:{1:'7'}},1),'7');
assert.equal(A.printedFormulaNumber({mode:'native-library'},1,'（7）'),'7','legacy library behavior preserved');
assert.equal(A.standaloneFormulaNumber(' ⟦EQ-001⟧（3） '),1);assert.equal(A.standaloneFormulaNumber('⟦EQ-002⟧'),2);assert.equal(A.standaloneFormulaNumber('文字⟦EQ-003⟧（7）'),null);
assert.deepEqual(Array.from(A.sideBySideFormulaNumbers('⟦EQ-007⟧     ⟦EQ-008⟧')),[7,8]);
assert.equal(A.sideBySideFormulaNumbers('⟦EQ-007⟧'),null,'single display formula stays on formula()');
assert.equal(A.sideBySideFormulaNumbers('⟦EQ-007⟧ ⟦EQ-008⟧（3）'),null,'numbered lines are never guessed as unnumbered rows');
assert.equal(A.sideBySideFormulaNumbers('甲⟦EQ-007⟧ ⟦EQ-008⟧'),null,'text with formulas stays inline');
const entry={number:1,path:'formula.idms',sha256:'a'.repeat(64),widthMm:4,heightMm:3,basePointSize:10.5};
const source={mode:'native-idms',entries:[entry]};
function nativeGroup(options={}){
 const labels={'formula-native-paste':'true','formula-base-point-size':'10.5'};
 const g={constructor:{name:'Group'},allGraphics:[],absoluteHorizontalScale:100,absoluteVerticalScale:100,geometricBounds:[0,0,3,4],parent:{},extractLabel:k=>labels[k]||'',insertLabel(k,v){labels[k]=v},getElements(){return [this]},...options};
 g.anchoredObjectSettings={insertAnchoredObject(point){if(point.anchor)point.anchor(g)}};return g;
}
let object=nativeGroup(),places=0;const anchorStory={insertionPoints:[]},point={parentStory:{getElements:()=>[anchorStory]},index:0};anchorStory.insertionPoints[0]=point;const document={pages:[{place(file){places++;assert.equal(file.path,'formula.idms');return [object]}}]};
assert.equal(A.insertNativeFormula(document,point,1,source,null),object);assert.equal(object.label,'source-formula-1');assert.equal(object.extractLabel('formula-idms-sha256'),entry.sha256);
let staleValid=true,rebound=false;
const reboundPoint={anchor(){assert.equal(staleValid,false);rebound=true}},reboundStory={insertionPoints:{4:reboundPoint}};
const stalePoint={index:4,parentStory:{getElements:()=>[reboundStory]},anchor(){throw Error('STALE_INSERTION_POINT')}};
A.insertNativeFormula({pages:[{place(){staleValid=false;return [nativeGroup()]}}]},stalePoint,1,source,null);
assert.equal(rebound,true,'anchor is rebound to the stored story position after IDMS placement');
for(const [options,error] of [[{allGraphics:[{}]},'FORMULA_NOT_NATIVE_GROUP'],[{constructor:{name:'Rectangle'}},'FORMULA_NOT_NATIVE_GROUP'],[{absoluteHorizontalScale:99},'FORMULA_SCALE'],[{geometricBounds:[0,0,3,4.2]},'FORMULA_NATIVE_SIZE'],[{extractLabel:()=>''},'FORMULA_NATIVE_PROVENANCE']]){
 object=nativeGroup(options);assert.throws(()=>A.insertNativeFormula(document,point,1,source,null),new RegExp(error));
}
assert.throws(()=>A.idmsEntry({entries:[entry,entry]},1),/FORMULA_IDMS_ENTRY/);
assert.throws(()=>A.insertNativeFormula({},point,1,{mode:'pdf'},null),/FORMULA_MODE/);
assert.throws(()=>A.insertNativeFormula({},point,1,{mode:'native-idms',entries:[{...entry,path:'missing.idms'}]},null),/FORMULA_IDMS_MISSING/);
// Live paragraph offsets emulate ID's UTF-16 character positions; object insertion must preserve both neighbors and their formatting.
let text='𠮷甲⟦EQ-001⟧乙⟦EQ-002⟧丙\r',format=Array.from({length:text.length},(_,i)=>({id:i,italic:i===2}));
const originalText=text,originalFormat=format.slice();const inserted=[];
const story={insertionPoints:new Proxy({}, {get(_,key){return {index:+key,parentStory:{getElements:()=>[story]},anchor(g){text=text.slice(0,+key)+'\uFFFC'+text.slice(+key);format.splice(+key,0,{anchor:true});g.parent={};inserted.push(g)}}}})};
const p={parentStory:story,get contents(){return text},characters:new Proxy({itemByRange(a,b){return {remove(){text=text.slice(0,a)+text.slice(b+1);format.splice(a,b-a+1)}}}}, {get(o,key){if(key in o)return o[key];return {index:+key}}})};
A.inlineFormulas({pages:[{place(){return [nativeGroup()]}}]},p,A.formulaMarkers(originalText),{formulas:{...source,entries:[entry,{...entry,number:2}]}},null);
assert.equal(text,'𠮷甲\uFFFC乙\uFFFC丙\r');assert.equal(format[2],originalFormat[2]);assert.equal(format[4],originalFormat[11]);
assert.equal(inserted.length,2);assert.equal(inserted[0].label,'source-formula-2');assert.equal(inserted[1].label,'source-formula-1');
for(const g of inserted){assert.equal(g.extractLabel('formula-display'),'false');assert.equal(g.extractLabel('formula-inline'),'true');assert.equal(g.parent.leading,15);assert.equal(g.extractLabel('formula-printed-number'),'')}
assert.equal(p.justification,undefined);assert.equal(p.pointSize,undefined);
console.log('PASS native IDMS contract, provenance, geometry, 100% scale, duplicate marker rejection, inline UTF-16 neighbors and source-only numbering');
