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
cell.contents='text label';cell.texts[0].justification='right';
assert(Array.from(rules.tableNativeIssues(ordinary)).some(issue=>issue.code==='TABLE_HORIZONTAL_ALIGN'),
  'ordinary nonnumeric text does not gain an unrestricted right-align exception');
cell.texts[0].justification='center';
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
const sourceStructure={widths:[1],headerRows:0,rows:[[{start:0,span:1}],[{start:0,span:1}]]};
assert.deepEqual(Array.from(rules.sourceDecimalColumns([['1.2'],['12.3']],sourceStructure)),[0]);
assert.deepEqual(Array.from(rules.sourceDecimalColumns([['1.2'],['2.3']],sourceStructure)),[],
  'equal digit shapes align naturally');
assert.deepEqual(Array.from(rules.sourceDecimalColumns([['1'],['12']],sourceStructure)),[],
  'integer count columns do not enter the decimal rule');
const decimalFrame={geometricBounds:[0,10,20,30]};
const decimalCells=['1.2','12.3'].map((value,index)=>{
  const c=makeCell('right');c.contents=value;c.parentRow={index};c.parentColumn={index:0};
  c.texts[0].justification='right';c.texts[0].paragraphs=[{justification:'right',rightIndent:1.2}];
  c.texts[0].characters=Array.from(value,()=>({horizontalOffset:0,parentTextFrames:[decimalFrame]}));
  c.texts[0].characters[value.indexOf('.')].horizontalOffset=20;
  return c;
});
const decimalTable={label:'source-table-4',headerRowCount:0,
  rows:decimalCells.map(cell=>({minimumHeight:5,height:5,autoGrow:true,cells:[cell]})),
  cells:decimalCells,columns:[{width:85.5,cells:decimalCells}]};
rules.normalizeOrdinaryTables([decimalTable],{tableKinds:[{number:4,kind:'ordinary'}]});
rules.normalizeOrdinaryTables([decimalTable],{tableKinds:[{number:4,kind:'ordinary'}]});
assert(decimalCells.every(c=>c.texts[0].justification==='right'&&c.texts[0].paragraphs[0].rightIndent===1.2),
  'normalization is idempotent and preserves right alignment and matching indents');
assert.deepEqual(Array.from(rules.tableNativeIssues(decimalTable)),[],
  'aligned decimal-point coordinates pass');
decimalCells[1].texts[0].characters[2].horizontalOffset=20.3;
assert(Array.from(rules.tableNativeIssues(decimalTable)).some(issue=>issue.code==='TABLE_DECIMAL_ALIGN'),
  'right alignment with equal indents is insufficient when decimal-point coordinates differ');
const assemblyContext=vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_article_assembly.jsxinc'),'utf8'),assemblyContext);
for(const kind of ['unclassified','algorithm','three-line'])
  assert.throws(()=>assemblyContext.JournalArticleAssembly.table(null,null,null,null,{kind}),/TABLE_KIND_UNSUPPORTED/);
console.log('PASS ordinary table native format restore, algorithm preservation, and unclassified preflight');
