const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const context=vm.createContext({TabStopAlignment:{CENTER_ALIGN:'center',RIGHT_ALIGN:'right'}});
vm.runInContext(fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_layout_rules.jsxinc'),'utf8'),context);
function run(columns,width,gutter,existing=[]){
  const tabs=existing.slice();tabs.add=function(spec){this.push(spec);};
  const frame={geometricBounds:[26,14.5,265,14.5+width],textFramePreferences:{textColumnCount:columns,textColumnGutter:gutter}};
  const p={contents:'\t\uFFFC\t（5）\r',tabStops:tabs,lines:[{}],insertionPoints:[{parentTextFrames:[frame]}]};
  const item={label:'source-formula-3',extractLabel(key){return key==='formula-display'?'true':'';},parent:{paragraphs:[p]}};
  context.JournalLayout.fitFormulaNumbers({allPageItems:[item]},true);
  assert.equal(p.contents,'\t\uFFFC\t（5）\r');
  return Array.from(tabs,t=>({position:t.position,alignment:t.alignment}));
}
const expected=[{position:42.75,alignment:'center'},{position:85.5,alignment:'right'}];
assert.deepEqual(run(1,85.5,0),expected);
assert.deepEqual(run(2,178,7),expected,'native two-column frames use the actual column width');
const custom=[{position:39,alignment:'center'},{position:82,alignment:'right'}];
assert.deepEqual(run(1,85.5,0,custom),custom,'preserve existing tab positions');
console.log('PASS missing display-formula tabs use column geometry and preserve existing stops');
