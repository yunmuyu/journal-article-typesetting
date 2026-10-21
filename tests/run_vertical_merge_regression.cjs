const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');
let source = fs.readFileSync(path.join(__dirname, '../2-导入_InDesign/journal_layout_rules.jsxinc'), 'utf8');
const seam = source.lastIndexOf('return {');
assert(seam >= 0, 'layout module export seam');
source = source.slice(0, seam) + source.slice(seam).replace('return {', 'return {testApplySourceMerges:applySourceMerges,testSourceTableCell:sourceTableCell,');
const context = {};
vm.runInNewContext(source, context);
const rules = context.JournalLayout;
function table(rows) {
    const result = {rows: rows.map(() => ({})), calls: 0};
    const cells = rows.map((row, ri) => row.map((text, ci) => ({contents: text, rowSpan: 1, removed: false, row: ri, column: ci})));
    cells.forEach(row => row.forEach(cell => {
        cell.merge = other => {
            assert.equal(other.column, cell.column);
            assert(other.row >= cell.row + cell.rowSpan);
            for (let row = cell.row + cell.rowSpan; row <= other.row; row++) {
                assert.equal(cells[row][cell.column].contents, '');
                cells[row][cell.column].removed = true;
            }
            cell.rowSpan = other.row - cell.row + 1;
            result.calls++;
        };
    }));
    result.rows.forEach((row, i) => Object.defineProperty(row, 'cells', {get: () => cells[i].filter(c => !c.removed)}));
    return result;
}
const rows = [['header', 'value']], merges = [];
for (const span of [10, 5, 5]) {
    const root = rows.length;
    for (let index = 0; index < span; index++) {
        rows.push([index ? '' : 'group' + root, 'value' + rows.length]);
        if (index) merges.push({tableIndex: 0, rowIndex: root + index, cellIndex: 0, intoRow: root, intoCell: 0, expectedRowSpan: span});
    }
}
const target = table(rows), config = {mergedEmptyCells: merges};
rules.testApplySourceMerges([target], config);
assert.equal(target.calls, 17);
for (const merge of merges) {
    assert.equal(target.rows[merge.intoRow].cells[0].rowSpan, merge.expectedRowSpan);
    assert.equal(rules.testSourceTableCell([target], config, {tableIndex: 0, rowIndex: merge.rowIndex, cellIndex: 1}).contents, 'value' + merge.rowIndex);
}
rules.testApplySourceMerges([target], config);
assert.equal(target.calls, 17, 'second application must be idempotent');
const legacy = table([['root', 'a'], ['', 'b']]);
const old = {mergedEmptyCells: [{tableIndex: 0, rowIndex: 1, cellIndex: 0, intoRow: 0, intoCell: 0}]};
rules.testApplySourceMerges([legacy], old);
rules.testApplySourceMerges([legacy], old);
assert.equal(legacy.rows[0].cells[0].rowSpan, 2);
const bad = table([['root'], ['nonempty']]);
assert.throws(() => rules.testApplySourceMerges([bad], old), /MERGE_NONEMPTY_CELL/);
assert.equal(bad.rows[1].cells[0].contents, 'nonempty');
const staggered = table([['A', 'B0', 'C0'], ['', 'B1', 'C1'], ['', '', 'C2'], ['A3', '', 'C3']]);
const mixed = {mergedEmptyCells: [
    {tableIndex:0,rowIndex:1,cellIndex:0,intoRow:0,intoCell:0,expectedRowSpan:3},
    {tableIndex:0,rowIndex:2,cellIndex:0,intoRow:0,intoCell:0,expectedRowSpan:3},
    {tableIndex:0,rowIndex:2,cellIndex:1,intoRow:1,intoCell:1,expectedRowSpan:3},
    {tableIndex:0,rowIndex:3,cellIndex:1,intoRow:1,intoCell:1,expectedRowSpan:3}]};
rules.testApplySourceMerges([staggered], mixed);
assert.equal(rules.testSourceTableCell([staggered], mixed, {tableIndex:0,rowIndex:2,cellIndex:2}).contents, 'C2');
assert.equal(rules.testSourceTableCell([staggered], mixed, {tableIndex:0,rowIndex:1,cellIndex:1}).rowSpan, 3);
rules.testApplySourceMerges([staggered], mixed);
assert.equal(staggered.calls, 4);
assert.throws(() => rules.testApplySourceMerges([target], {mergedEmptyCells:[{...merges[0],expectedRowSpan:4}]}), /MERGE_UNEXPECTED_SPAN/);
console.log('PASS vertical merges: 10/5/5 rows, idempotence, legacy, nonempty protection, staggered columns, expected-span mismatch');
