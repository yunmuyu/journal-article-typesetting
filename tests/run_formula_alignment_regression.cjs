const fs=require('fs'),p=require('path'),vm=require('vm'),assert=require('assert/strict');const source=fs.readFileSync(p.join(__dirname,'../2-导入_InDesign/journal_article_assembly.jsxinc'),'utf8');let c=vm.createContext({Justification:{LEFT_ALIGN:'LEFT'}});vm.runInContext(source,c);const target={justification:'RIGHT',tabStops:{everyItem:()=>({remove(){}}),add(){}}};c.JournalArticleAssembly.setFormulaTabs(target,[{position:38.5,alignment:1},{position:85.5,alignment:2}]);assert.equal(target.justification,'LEFT');assert.equal(c.JournalArticleAssembly.printedFormulaNumber({},17),null);assert.equal(c.JournalArticleAssembly.printedFormulaNumber({displayNumbers:{17:3}},17),'3');console.log('PASS formula tabs restore left paragraph alignment in new and existing QA');
const rulesSource=fs.readFileSync(p.join(__dirname,'../2-导入_InDesign/journal_layout_rules.jsxinc'),'utf8');
const testRules=rulesSource.replace('return {projectTableRuns:', 'return {nearestFormulaTab:nearestFormulaTab,projectTableRuns:');
vm.runInContext(testRules,c);
const fitTab=c.JournalLayout.nearestFormulaTab;
assert.equal(fitTab(42.75,38,()=>true),42.75);
const shifted=fitTab(42.75,38,x=>x<=41.95);
assert(shifted<=41.95&&41.95-shifted<=.005);
assert.equal(fitTab(42.75,53,()=>false),null);
assert.equal(fitTab(42.75,38,()=>false),null);
console.log('PASS numbered formula tab selection preserves center when possible and chooses minimum feasible shift');

const bandContext = vm.createContext({SpanColumnTypeOptions: {SPAN_COLUMNS: 'span'}});
vm.runInContext(rulesSource.replace('return {projectTableRuns:', 'return {nativeBandLineBottom:nativeBandLineBottom,projectTableRuns:'), bandContext);
const layout = bandContext.JournalLayout;
const frame = {id: 1, geometricBounds: [26, 15, 265, 193]};
const makeLine = (contents, index, x, baseline, allPageItems = []) => ({
    contents, horizontalOffset: x, baseline, paragraphs: [{allPageItems}],
    insertionPoints: [{index, parentTextFrames: [frame]}]
});
function Character(index) { this.index = index; }
const formula = {label: 'source-formula-59', parent: new Character(30), geometricBounds: [258, 138, 263.47, 160],
    extractLabel: () => 'unnumbered'};
const intro = makeLine('为了叙述方便，记：', 18, 108, 257.21);
const anchorLine = makeLine('\uFFFC', 30, 100, 262.81, [formula]);
anchorLine.insertionPoints[-1] = {index: 32};
intro.insertionPoints[-1] = {index: 30};
const other = makeLine('\uFFFC', 32, 138, 264, [{...formula, parent: new Character(32), extractLabel: () => 'false'}]);
other.insertionPoints[-1] = {index: 34};
frame.lines = [intro, anchorLine, other];
assert.equal(layout.nativeFlowBands(frame).bands[0].right.length, 2);
assert.equal(layout.nativeBandLineBottom(anchorLine), 263.47);
assert.equal(layout.nativeBandLineBottom(intro), 257.21);
console.log('PASS native column includes standalone formula ink and skips unrelated anchor-only lines');
