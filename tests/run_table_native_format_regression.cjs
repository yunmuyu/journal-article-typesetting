const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const assert=require('node:assert/strict');
const context=vm.createContext({
  Justification:{CENTER_ALIGN:'center'},VerticalJustification:{CENTER_ALIGN:'middle'},
  RowTypes:{HEADER_ROW:'header'}
});
vm.runInContext(fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_layout_rules.jsxinc'),'utf8'),context);
const rules=context.JournalLayout;
const text=justification=>({justification,lines:[{}],pointSize:9,leading:12});
const makeCell=justification=>{
  const cell={texts:[text(justification)],properties:{topInset:9,bottomInset:9,leftInset:9,rightInset:9,
    verticalJustification:'top',topEdgeStrokeWeight:0,bottomEdgeStrokeWeight:0,leftEdgeStrokeWeight:0,rightEdgeStrokeWeight:0}};
  for(const key of Object.keys(cell.properties))Object.defineProperty(cell,key,{get(){return this.properties[key];}});
  return cell;
};
const ordinary={label:'source-table-1',rows:[{minimumHeight:1.058,height:5,autoGrow:false,cells:[makeCell('left')]}]};
const algorithm={label:'source-table-2',rows:[{minimumHeight:5,height:84.608,autoGrow:true,cells:[makeCell('left')]}]};
const unknown={label:'source-table-3',rows:[{minimumHeight:4.175,height:4.175,autoGrow:false,cells:[makeCell('left')]}]};
for(const table of [ordinary,algorithm,unknown]){
  table.cells=table.rows.flatMap(row=>row.cells);table.columns=[{width:85.5}];
}
const kinds=[{kind:'ordinary'},{kind:'algorithm'},{kind:'unclassified'}];
assert.equal(typeof rules.normalizeOrdinaryTables,'function');
assert.throws(()=>rules.normalizeOrdinaryTables([ordinary,algorithm,unknown],{tableKinds:kinds}),/TABLE_KIND_REQUIRED/);
assert.equal(ordinary.rows[0].minimumHeight,1.058,'unclassified gate must run before mutation');
rules.normalizeOrdinaryTables([ordinary,algorithm],{tableKinds:kinds.slice(0,2)});
const row=ordinary.rows[0],cell=row.cells[0];
assert.equal(row.minimumHeight,5);
assert.equal(row.height,5,'actual row height is not assigned by the format restore');
assert.equal(row.autoGrow,true);
assert.equal(cell.texts[0].justification,'center');
for(const edge of ['top','bottom','left','right']){
  assert.equal(cell.properties[edge+'Inset'],.5);
  assert.equal(cell.properties[edge+'EdgeStrokeWeight'],.5);
}
assert.equal(cell.properties.verticalJustification,'middle');
assert.deepEqual(Array.from(rules.tableNativeIssues(ordinary)),[]);
for(const approved of [4.6,4.8,5.5]){
  row.minimumHeight=approved;
  rules.normalizeOrdinaryTables([ordinary,algorithm],{tableKinds:kinds.slice(0,2)});
  assert.equal(row.minimumHeight,approved,'format restore preserves an approved bottom-plan minimum');
}
row.minimumHeight=5;
ordinary.columns[0].width=0;
assert(Array.from(rules.tableNativeIssues(ordinary)).some(issue=>issue.code==='TABLE_WIDTH_INVALID'));
ordinary.columns[0].width=85.5;
row.minimumHeight=1.058;
assert(Array.from(rules.tableNativeIssues(ordinary)).some(issue=>issue.code==='TABLE_MINIMUM_HEIGHT'));
row.minimumHeight=undefined;row.autoGrow=undefined;row.height=4.175;
const historicalIssues=Array.from(rules.tableNativeIssues(ordinary));
for(const code of ['TABLE_MINIMUM_HEIGHT','TABLE_AUTO_GROW','TABLE_HEIGHT'])
  assert(historicalIssues.some(issue=>issue.code===code),code);
row.autoGrow=true;row.height=5;
row.minimumHeight=5;
cell.properties.topEdgeStrokeWeight=null;
assert(Array.from(rules.tableNativeIssues(ordinary)).some(issue=>issue.code==='TABLE_EDGE_STROKE'));
cell.properties.topEdgeStrokeWeight=.5;
row.height=84.608;cell.texts[0].lines=[{},{}];
assert.deepEqual(Array.from(rules.tableNativeIssues(ordinary)),[],'multi-line height grows naturally');
assert.equal(algorithm.rows[0].height,84.608);
assert.equal(algorithm.rows[0].cells[0].texts[0].justification,'left');
const assemblyContext=vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_article_assembly.jsxinc'),'utf8'),assemblyContext);
for(const kind of ['unclassified','algorithm','three-line'])
  assert.throws(()=>assemblyContext.JournalArticleAssembly.table(null,null,null,null,{kind}),/TABLE_KIND_UNSUPPORTED/);
console.log('PASS ordinary table native format restore, algorithm preservation, and unclassified preflight');
