const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../2-导入_InDesign/journal_layout_rules.jsxinc'), 'utf8');
const context = vm.createContext({
    SpanColumnTypeOptions: { SPAN_COLUMNS: 'span' },
    VerticalJustification: { CENTER_ALIGN: 'center' },
});
const frame = {
    id: 1,
    parentPage: { id: 10, name: '33', documentOffset: 0 },
    geometricBounds: [26, 0, 265, 178],
    textFramePreferences: { textColumnCount: 2 },
};
function line(horizontalOffset, baseline, index) {
    return {
        horizontalOffset, baseline, ascent: 3, descent: 1, contents: '正文',
        paragraphs: [{ spanColumnType: 'single' }],
        insertionPoints: { 0: { parentTextFrames: [frame], index }, '-1': { index: index + 1 } },
    };
}
frame.lines = [line(10, 157, 0), line(100, 222, 2)];
const cellLines = [line(15, 256, 5)];
cellLines[-1] = cellLines[0];
const table = { rows: [{ height: 10, cells: [{ rowSpan: 1, verticalJustification: 'center', texts: [{ lines: cellLines }] }] }] };
frame.tables = { everyItem: () => ({ getElements: () => [table] }) };

const exportAt = source.lastIndexOf('return {');
assert.ok(exportAt > 0);
vm.runInContext(source.slice(0, exportAt) + 'return {auditColumnGeometry:auditColumnGeometry,' +
    source.slice(exportAt + 'return {'.length), context);
const pages = [];
pages[-1] = { id: 11, documentOffset: 1 };
const errors = [];
context.JournalLayout.auditColumnGeometry({ pages }, {}, [frame], (code, detail) => errors.push([code, detail]), []);
assert.deepEqual(errors.filter(([code]) => code === 'LARGE_EMPTY_REGION'),
    [['LARGE_EMPTY_REGION', 'page 33 right column unexplained 42.000 mm']]);
assert.ok(errors.some(([code, detail]) => code === 'NATIVE_COLUMN_BOTTOM' && detail.startsWith('33/left 259.')));
assert.ok(errors.some(([code, detail]) => code === 'NATIVE_COLUMN_BOTTOM' && detail.startsWith('33/right 222 ')));
console.log('PASS a table fills only its own column for the native large-gap check');

const captionLine = line(10, 220, 6);
const rowLine = line(100, 40, 10);
const caption = { contents: '表 4 示例', insertionPoints: captionLine.insertionPoints, lines: [captionLine], keepWithNext: 0 };
const rowText = { insertionPoints: rowLine.insertionPoints, lines: [rowLine] };
const row = { cells: [{ texts: [rowText] }] };
const anchor = { tables: [{ label: 'source-table-4', headerRowCount: 1, rows: [row, row] }], keepWithPrevious: false };
const body = { paragraphs: [caption, anchor], overflows: false };
const document = { recompose: () => { if (anchor.keepWithPrevious) captionLine.horizontalOffset = 100; } };
assert.equal(context.JournalLayout.joinSeparatedWideTableCaptions(document, body).length, 0);
const repairs = context.JournalLayout.joinSeparatedWideTableCaptions(document, body, true);
assert.equal(repairs[0].accepted, true);
assert.equal(caption.keepWithNext, 1);
captionLine.horizontalOffset = 10;
caption.keepWithNext = 0;
anchor.keepWithPrevious = false;
const failed = context.JournalLayout.joinSeparatedWideTableCaptions({ recompose: () => {} }, body, true);
assert.equal(failed[0].accepted, false);
assert.equal(caption.keepWithNext, 0);
assert.equal(anchor.keepWithPrevious, false);
console.log('PASS split table caption repair detects native columns and rolls back failures');
