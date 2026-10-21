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
console.log('PASS three-tier regression contract');
