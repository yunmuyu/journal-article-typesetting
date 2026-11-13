const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const context=vm.createContext({});
const source=fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_article_assembly.jsxinc'),'utf8');
vm.runInContext(source,context);
const fit=context.JournalArticleAssembly.defaultTableWidths;
assert.equal(typeof fit,'function');
const structure={widths:[100,2000],rows:[[{start:0,span:1},{start:1,span:1}]]};
const widths=Array.from(fit([['轮次','内容']],structure));
assert.ok(widths[0]>=7.4);
assert.ok(Math.abs(widths.reduce((a,b)=>a+b)-85.5)<1e-8);
assert.deepEqual(Array.from(fit([['A','B']],structure)),[85.5*100/2100,85.5*2000/2100]);
const improve=context.JournalArticleAssembly.improveTableWidths;
assert.equal(typeof improve,'function');
const sourceWidths=[42.75,42.75], measured=[];
const objective=widths=>{measured.push([...widths]);return widths[0]<57 ? 20 : 15;};
const optimized=Array.from(improve(sourceWidths,[7.4,2],objective));
assert.ok(optimized[0]>=57,'measured total row height, not source ratio, chooses first column');
assert.equal(optimized.reduce((sum,width)=>sum+width),85.5);
assert.ok(optimized[1]>=2);
assert.ok(measured.length>1,'candidate widths are evaluated');
const recovered=Array.from(improve(sourceWidths,[7.4,2],widths=>widths[0]>=50?15:Infinity));
assert.ok(recovered[0]>=50,'an overflowing starting width must search for a feasible candidate');
let noFeasibleCalls=0;
assert.throws(()=>improve(sourceWidths,[7.4,2],()=>{noFeasibleCalls++;return Infinity;}),/TABLE_WIDTH_NO_FEASIBLE/);
assert.ok(noFeasibleCalls<=300,'a table with no feasible column widths terminates');
const unchanged=Array.from(improve(sourceWidths,[7.4,2],()=>15));
assert.deepEqual(unchanged,sourceWidths,'equal row height does not make an arbitrary width change');
const legible=Array.from(improve(sourceWidths,[7.4,2],widths=>
  widths[0]>=44?{height:16,orphans:0}:{height:15,orphans:1}));
assert.ok(legible[0]>=44,'removing an actual orphan takes priority over a smaller table');
const fewerWraps=Array.from(improve(sourceWidths,[7.4,2],widths=>
  ({height:15,orphans:0,lines:widths[0]>=44?3:4})));
assert.ok(fewerWraps[0]>=44,'at the same height and orphan count choose fewer wraps');
let boundedCalls=0;
improve(Array(8).fill(85.5/8),Array(8).fill(2),()=>1000-++boundedCalls);
assert.ok(boundedCalls<=300,'native recompose search remains bounded for wide tables');
const styleName='表格正文默认';
const tableCells=[0,1].map(()=>({texts:[{applyParagraphStyle(){},properties:{}}],overflows:false}));
const nativeTable={columns:[{width:0},{width:0}],rows:[{height:20,cells:tableCells}],cells:tableCells,
  insertLabel(key,value){this[key]=value;}};
const nativeDocument={allParagraphStyles:[{name:styleName}],recompose(){
  nativeTable.rows[0].height=nativeTable.columns[0].width>=57?15:20;
}};
const nativeContext=vm.createContext({JournalLayout:{normalizeOrdinaryTables(){}},
  app:{fonts:{itemByName(){return {isValid:true,status:'installed'};}}},FontStatus:{INSTALLED:'installed'},
  RowTypes:{HEADER_ROW:'header'}});
vm.runInContext(source,nativeContext);
const paragraph={characters:{length:1},insertionPoints:[{tables:{add(){return nativeTable;}}}]};
const measuredTable=nativeContext.JournalArticleAssembly.table(nativeDocument,paragraph,[['left','right']],
  {widths:[1000,1000],rows:[[{start:0,span:1},{start:1,span:1}]],headerRows:0},
  {number:1,kind:'ordinary'});
nativeContext.JournalArticleAssembly.optimizeNativeTable(nativeDocument,measuredTable,[['left','right']],
  {widths:[1000,1000],rows:[[{start:0,span:1},{start:1,span:1}]]});
assert.equal(measuredTable.columns[0].width>=57,true,'native row heights choose the final widths');
assert.equal(measuredTable['journal-table-kind'],'ordinary');
const overflowCells=[{overflows:false,texts:[{lines:[]}]}];
const overflowTable={columns:[{width:42.75},{width:42.75}],rows:[{height:10}],cells:overflowCells};
const overflowDoc={recompose(){overflowCells[0].overflows=overflowTable.columns[0].width<50;}};
nativeContext.JournalArticleAssembly.optimizeNativeTable(overflowDoc,overflowTable,[['a','b']],
  {widths:[1,1],rows:[[{start:0,span:1},{start:1,span:1}]]});
assert.ok(overflowTable.columns[0].width>=50,'native overflow at source ratio recovers with a feasible width');
overflowTable.columns[0].width=42.75;overflowTable.columns[1].width=42.75;
overflowDoc.recompose=()=>{overflowCells[0].overflows=true;};
assert.throws(()=>nativeContext.JournalArticleAssembly.optimizeNativeTable(overflowDoc,overflowTable,[['a','b']],
  {widths:[1,1],rows:[[{start:0,span:1},{start:1,span:1}]]}),/TABLE_WIDTH_NO_FEASIBLE/);
assert.deepEqual(overflowTable.columns.map(c=>c.width),[42.75,42.75],
  'no-feasible-width failure rolls all native columns back');
const formulaTable={label:'source-table-2',columns:[{width:42.75},{width:42.75}],rows:[{height:10}]};
const formulaCell=(column,width)=>({
  columnSpan:1,parentColumn:{index:column},leftInset:.5,rightInset:.5,overflows:false,
  get width(){return formulaTable.columns[column].width;},
  texts:[{lines:[],allPageItems:[{label:'source-formula-'+column,geometricBounds:[0,0,4,width]}]}]
});
formulaTable.cells=[formulaCell(0,49),formulaCell(1,32)];
const formulaStructure={widths:[1,1],rows:[[{start:0,span:1},{start:1,span:1}]]};
nativeContext.JournalArticleAssembly.optimizeNativeTable({recompose(){}},formulaTable,[['a','b']],formulaStructure);
assert.ok(formulaTable.columns[0].width>=50.02-.001,'formula and both insets fit even without a native overflow flag');
assert.ok(formulaTable.columns[1].width>=33.02-.001);
formulaTable.cells=[formulaCell(0,55),formulaCell(1,36)];
const beforeCapacity=formulaTable.columns.map(c=>c.width);
assert.throws(()=>nativeContext.JournalArticleAssembly.optimizeNativeTable({recompose(){}},formulaTable,[['a','b']],formulaStructure),/TABLE_FORMULA_WIDTH_CAPACITY/);
assert.deepEqual(formulaTable.columns.map(c=>c.width),beforeCapacity);
console.log('PASS two-CJK table cells receive a usable minimum column width while total table width stays fixed');
// A decimal offset measured in the old wide column must not make a narrow trial falsely overflow.
const staleParagraph={leftIndent:20,rightIndent:0,firstLineIndent:0};
const staleCells=[{overflows:false,texts:[{contents:'0.690 5',paragraphs:[staleParagraph],lines:[]}]}];
const staleTable={columns:[{width:20},{width:65.5}],rows:[{height:5}],cells:staleCells};
const staleDoc={recompose(){staleCells[0].overflows=staleParagraph.leftIndent+8>staleTable.columns[0].width;}};
nativeContext.JournalArticleAssembly.optimizeNativeTable(staleDoc,staleTable,[['2.00','text']],
  {widths:[20,65.5],rows:[[{start:0,span:1},{start:1,span:1}]]},{maxEvaluations:4});
assert.equal(staleParagraph.leftIndent,0);
assert.equal(staleCells[0].overflows,false);
assert.equal(staleCells[0].texts[0].noBreak,true,'grouping spaces must not split numeric data across lines');
assert.equal(staleTable.columns[0].width,20,'do not widen a fitting column to compensate for stale indentation');
console.log('PASS narrow table trials clear width-dependent decimal offsets');
