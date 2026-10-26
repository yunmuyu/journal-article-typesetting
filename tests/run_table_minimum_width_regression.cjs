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
const overflowCells=[{overflows:false}];
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
console.log('PASS two-CJK table cells receive a usable minimum column width while total table width stays fixed');
