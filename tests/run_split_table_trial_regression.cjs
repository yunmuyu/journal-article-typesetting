const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../2-导入_InDesign/journal_split_table_trial.jsxinc'), 'utf8'), context);
const makeFrame = (offset, columns, tables = []) => ({
    parentPage: {documentOffset: offset},
    textFramePreferences: {textColumnCount: columns},
    tables,
});
const cases = [
    [makeFrame(1, 2), makeFrame(2, 2), makeFrame(3, 2)],
    [makeFrame(1, 2), makeFrame(3, 2, [{}]), makeFrame(4, 2)],
    [makeFrame(1, 1), makeFrame(2, 2, [{}]), makeFrame(3, 2)],
    [makeFrame(1, 2), makeFrame(2, 2, [{}, {}]), makeFrame(3, 2)],
];
for (const frames of cases) {
    const result = context.trialSplitTablePage(null, {contents: '正文', textContainers: frames});
    assert.equal(result.status, 'skipped');
}
console.log('PASS split trial skips no-table, nonadjacent, single-column and ambiguous multiple-table layouts');

const refFrame = makeFrame(3, 2);
refFrame.allGraphics = [];
const refLine = (baseline, name='参考文献 内容') => ({
    baseline, paragraphs:[{appliedParagraphStyle:{name}}]
});
let refBands;
context.JournalLayout={rules:{tolerance:.01,tailTolerance:.1},nativeFlowBands:()=>({bands:refBands})};
for (const band of [
    {cut:true,left:[refLine(90.1)],right:[refLine(90)]},
    {cut:false,left:[refLine(91.2)],right:[refLine(90)]},
    {cut:false,left:[refLine(90.09)],right:[refLine(90)]},
]) {
    refBands=[band];
    assert.equal(context.trialSplitReferenceTail(null,{textContainers:[refFrame]}).status,'skipped');
}
console.log('PASS fixed-break tail split leaves spans, tails without adjustable lines and aligned tails untouched');

function mixedTail(initial, requestedCut) {
    const leading = new Map([[5, 15], [15, 13]]);
    function line(start, end, baseline, style) {
        const characters = [{index:start}];
        characters[-1] = {index:end-1, get leading() { return leading.get(start); }};
        const insertionPoints = [{index:start}];
        insertionPoints[-1] = {index:end};
        return {characters, insertionPoints, paragraphs:[{appliedParagraphStyle:{name:style}}], get baseline() { return baseline(); }};
    }
    const leftLines = [
        line(0, 5, () => 30, '正文'),
        line(5, 10, () => 90 + initial + 3 * (leading.get(5) - 15), '正文'),
    ];
    const rightLines = [
        line(10, 15, () => 30, '参考文献 内容'),
        line(15, 20, () => 90 + 5 * (leading.get(15) - 13), '参考文献 内容'),
    ];
    leftLines[-1] = leftLines[1];
    rightLines[-1] = rightLines[1];
    const right = {lines:rightLines,textFramePreferences:{},insertLabel(){}};
    const left = {
        ...makeFrame(3, 2),
        allGraphics:[], lines:leftLines, geometricBounds:[25,0,100,180],
        extractLabel(){return 'article';},
    };
    left.textFramePreferences.textColumnGutter = 8;
    left.parentPage.textFrames = {add:() => right};
    const body = {
        textContainers:[left], contents:'完整正文和参考文献', overflows:false,
        characters:{itemByRange(first){return {set leading(value){leading.set(first,value);}};}},
    };
    context.JournalLayout.last = frame => frame.lines[-1].baseline;
    refBands = [{cut:false,left:leftLines,right:rightLines}];
    return {result:context.trialSplitReferenceTail({recompose(){}},body,requestedCut),leading,left,right};
}
const mixed = mixedTail(2.2);
assert.equal(mixed.result.status, 'accepted');
assert.equal(mixed.result.cut, 10);
assert.ok(Math.abs(mixed.result.afterMm) <= .1);
assert.equal(mixed.left.nextTextFrame, mixed.right);
assert.ok(mixed.leading.get(5) >= 14.8);
assert.ok(mixed.leading.get(15) <= 13.4);
assert.equal(mixed.leading.has(0), false);
assert.equal(mixed.leading.has(10), false);
assert.equal(mixedTail(3).result.reason, 'REFERENCE_TAIL_CAPACITY');
assert.equal(mixedTail(2.2,{index:9,deltaPt:6}).result.reason, 'REFERENCE_TAIL_REQUESTED_BREAK_INVALID');
assert.equal(mixedTail(2.2,{index:5,deltaPt:6}).result.reason, 'REFERENCE_TAIL_REQUESTED_BREAK_INVALID');
console.log('PASS mixed tail can close a larger gap at the fixed cut and rejects insufficient leading capacity');
