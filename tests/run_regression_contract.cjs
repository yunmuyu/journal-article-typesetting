const assert = require('node:assert/strict');
const { compare } = require('../2-导入_InDesign/journal_regression_contract.cjs');
const para = (text, style = '正文_wrd_1') => ({
  ordinal: 0, text, style, tabs: [], properties: { firstLineIndent: 7, startParagraph: 'ANYWHERE' },
  ranges: [{ start: 0, text, font: '现 宋体-1\tRegular', fontStyle: 'Regular', pointSize: 10.5,
    position: 'NORMAL', baselineShift: 0, horizontalScale: 100, verticalScale: 100, tracking: 0, leading: 15 }]
});
const base = {
  schemaVersion: 1, unavailable: [], compositeFonts: [], objects: [],
  stories: [{ role: 'body', paragraphs: [para('原文内容。\r')], frames: [], tables: [] },
    { role: 'front', paragraphs: [para('中图分类号：TP1\t文献标识码：A\t文章编号：000\r')],
      frames: [{ bounds: [30, 20, 150, 186], inset: [0, 0, 0, 0] }], tables: [] }]
};
const clone = value => JSON.parse(JSON.stringify(value));
for (const role of ['footer', 'doi']) base.stories.push({
  role, paragraphs: [], frames: [{ bounds: [240, 15, 265, 100], inset: [0, 0, 0, 0] }], tables: []
});
const check = candidate => compare(base, candidate);
assert.equal(check(clone(base)).mustMatchPassed, true);
let c = clone(base);
c.stories[0].paragraphs[0].ranges[0].leading = 15.8;
c.stories[0].paragraphs[0].ranges[0].tracking = 8.3;
c.stories[0].paragraphs[0].properties.startParagraph = 'NEXT_COLUMN';
c.stories[1].frames[0].bounds[2] += 4;
assert.equal(check(c).mustMatchPassed, true, 'legal solved values are not a replica requirement');
assert.equal(check(c).passed, false, 'mandatory comparison alone is not full quality acceptance');
c.stories[0].paragraphs[0].ranges[0].pointSize = 9;
assert(check(c).failures.some(x => x.code === 'CHARACTER_FORMAT' && x.field === 'pointSize'));
c = clone(base);
c.stories[1].paragraphs[0] = para(base.stories[1].paragraphs[0].text.replace(/\t/g, '  '));
assert(check(c).failures.some(x => x.code === 'TAB_CHARACTERS'));
c = clone(base);
c.stories[1].frames[0].bounds[0] += 2;
assert(check(c).failures.some(x => x.code === 'FIXED_ANCHOR'));
c = clone(base);
c.stories[0].paragraphs[0].ranges[0].leading = 0.1;
assert(check(c).failures.some(x => x.code === 'LEADING_RANGE'));
c = clone(base);
c.stories[0].paragraphs = [para('漏排内容。\r')];
assert(check(c).failures.some(x => x.code === 'CONTENT_MISSING'));
c = clone(base);
c.unavailable.push({ property: 'position' });
assert(check(c).failures.some(x => x.code === 'SNAPSHOT_INCOMPLETE'));
c = clone(base);
c.stories[0].paragraphs[0].ranges = [];
assert(check(c).failures.some(x => x.code === 'CHARACTER_UNMEASURED'));
const tb = { rows: 2, columns: 2, headerRowCount: 1, footerRowCount: 0,
  cells: [{ row: 0, column: 0, rowSpan: 2, columnSpan: 1, text: 'e', paragraphs: [para('e')] }] };
base.stories[0].tables = [tb];
c = clone(base);
c.stories[0].tables[0].cells[0].rowSpan = 1;
assert(check(c).failures.some(x => x.code === 'TABLE_MERGE'));

// Native table properties are a contract independent of naturally changing row height.
const native = clone(base);
const sourceTable = native.stories[0].tables[0];
sourceTable.kind = 'ordinary';
sourceTable.widths = [42.75, 42.75];
sourceTable.rowMetrics = [{height: 5, minimumHeight: 5, autoGrow: true},
  {height: 5, minimumHeight: 5, autoGrow: true}];
sourceTable.cells[0].properties = {
  topInset: .5, bottomInset: .5, leftInset: .5, rightInset: .5,
  verticalJustification: 'center', topEdgeStrokeWeight: .5,
  bottomEdgeStrokeWeight: .5, leftEdgeStrokeWeight: .5, rightEdgeStrokeWeight: .5
};
sourceTable.cells[0].paragraphs[0].properties.justification = 'center';
sourceTable.cells[0].paragraphs[0].ranges[0].leading = 12;
const verifyTable = change => { const candidate = clone(native); change(candidate.stories[0].tables[0]);
  return compare(native, candidate, {passed: true}); };
for (const field of Object.keys(sourceTable.cells[0].properties)) {
  const result = verifyTable(table => { table.cells[0].properties[field] = 9; });
  assert(result.failures.some(x => x.code === 'TABLE_CELL_FORMAT' && x.field === field), field);
}
assert(verifyTable(table => { table.cells[0].paragraphs[0].properties.justification = 'left'; })
  .failures.some(x => x.code === 'PARAGRAPH_FORMAT' && x.field === 'justification'));
assert(verifyTable(table => { table.rowMetrics[0].minimumHeight = 1.058; })
  .failures.some(x => x.code === 'TABLE_MINIMUM_HEIGHT'));
assert(verifyTable(table => { table.rowMetrics[0].autoGrow = false; })
  .failures.some(x => x.code === 'TABLE_AUTO_GROW'));
assert(verifyTable(table => { table.rowMetrics[0].minimumHeight = null; })
  .failures.some(x => x.code === 'TABLE_MINIMUM_HEIGHT'));
assert(verifyTable(table => { table.widths = [0, 85.5]; })
  .failures.some(x => x.code === 'TABLE_WIDTH_INVALID'));
assert(verifyTable(table => { table.widths = [50, 50]; })
  .failures.some(x => x.code === 'TABLE_TOTAL_WIDTH'));
let permitted = verifyTable(table => { table.widths = [40, 45.5]; table.rowMetrics[0].height = 7; });
assert.equal(permitted.passed, true, JSON.stringify(permitted.failures));
assert(permitted.compliantVariationCandidates.some(x => x.fields.includes('widths')));
permitted = verifyTable(table => { table.rowMetrics[0].height = 7; table.rowMetrics[0].minimumHeight = 5; });
assert.equal(permitted.passed, true, JSON.stringify(permitted.failures));
const algorithmReference = clone(native);
const algorithmTable = algorithmReference.stories[0].tables[0];
algorithmTable.kind = 'algorithm';
algorithmTable.cells[0].paragraphs[0].properties.justification = 'left';
algorithmTable.rowMetrics[1].height = 84.608;
const algorithmCandidate = clone(algorithmReference);
algorithmCandidate.stories[0].tables[0].rowMetrics[1].height = 90;
assert.equal(compare(algorithmReference, algorithmCandidate, {passed:true}).passed, true,
  'algorithm body left alignment and natural multi-line height are preserved');
algorithmCandidate.stories[0].tables[0].cells[0].properties.leftInset = 9;
assert(compare(algorithmReference, algorithmCandidate).failures.some(x=>x.code==='TABLE_CELL_FORMAT'));
console.log('PASS three-tier regression contract');
