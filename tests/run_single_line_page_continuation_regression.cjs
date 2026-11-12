const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const context = vm.createContext({SpanColumnTypeOptions: {SPAN_COLUMNS: 'span'}});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../2-导入_InDesign/journal_layout_rules.jsxinc'), 'utf8'), context);
const paragraph = (index, spanColumnType) => ({
    index, contents: '测试正文。', spanColumnType, appliedParagraphStyle: {name: '正文'}
});
const body = paragraph(3);
const span = paragraph(7, 'span');
const line = (p, page, baseline, horizontalOffset) => ({
    contents: '测试。', paragraphs: [p], baseline, horizontalOffset,
    insertionPoints: [{parentTextFrames: [{parentPage: {id: page, name: String(page)}}]}]
});
const inspect = context.JournalLayout.singleLinePageContinuations;
assert.equal(inspect({lines: [line(body, 2), line(body, 3), line(span, 3)]}).length, 1);
assert.equal(inspect({lines: [line(body, 2), line(body, 3)]}).length, 1);
assert.equal(inspect({lines: [line(body, 2), line(body, 3), line(body, 3), line(span, 3)]}).length, 0);
assert.equal(inspect({lines: [line(body, 2, 264), line(body, 3, 29), line(body, 3, 29), line(span, 3, 32)]}).length, 1);
const aligned = {lines: [line(body, 2, 264), line(body, 3, 29, 15), line(body, 3, 29, 108), line(span, 3, 32)]};
assert.equal(inspect(aligned).length, 1);
const fullWidth = line(body, 3, 29, 15);
const continuationFrame = fullWidth.insertionPoints[0].parentTextFrames[0];
continuationFrame.extractLabel = key => key === 'journal-full-width-continuation' ? 'true' : '';
continuationFrame.textFramePreferences = {textColumnCount:1};
continuationFrame.lines = [fullWidth];
continuationFrame.geometricBounds = [26,15,31,193];
continuationFrame.nextTextFrame = {
    parentPage:{id:3}, textFramePreferences:{textColumnCount:2}, geometricBounds:[31,15,265,193]
};
assert.equal(inspect({lines:[line(body, 2, 264),fullWidth,line(span, 3, 32)]}).length, 0);
continuationFrame.geometricBounds[3] = 100;
assert.equal(inspect({lines:[line(body, 2, 264),fullWidth,line(span, 3, 32)]}).length, 1);
assert.equal(inspect({lines: [line(body, 2, 264), line(body, 3, 29), line(body, 3, 34), line(span, 3, 37)]}).length, 0);
assert.equal(inspect({lines: [line(body, 2), line(body, 3), line(paragraph(5), 3)]}).length, 0);
assert.equal(inspect({lines: [line(body, 2), line(body, 2), line(span, 2)]}).length, 0);
assert.equal(inspect({lines: [line(body, 2), line(paragraph(5), 3)]}).length, 0);
console.log('PASS single-line page continuation uses actual pages and distinguishes ordinary flow and two-column bands');
