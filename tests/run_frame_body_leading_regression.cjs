const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../2-导入_InDesign/journal_layout_rules.jsxinc'), 'utf8'), context);
const align = context.JournalLayout.alignFrameBodyLeading;
const pointToMm = 25.4 / 72;

function mockFrame(rows) {
  const characters = [];
  const changes = [];
  const body = {
    id: 1,
    overflows: false,
    characters: {
      itemByRange(start, end) {
        const selected = characters.slice(start, end + 1);
        const styles = selected.map((character) => ({
          characters: { 0: character, '-1': character },
          leading: character.leading,
        }));
        return {
          set leading(value) {
            changes.push({ start, end });
            for (const character of selected) character.leading = value;
          },
          textStyleRanges: { everyItem: () => ({ getElements: () => styles }) },
        };
      },
    },
  };
  const frame = {
    id: 2,
    parentStory: body,
    textFramePreferences: { textColumnCount: 1 },
    tables: { everyItem: () => ({ getElements: () => [] }) },
  };
  frame.lines = rows.map(({ text = '正文', leads = [15, 15], style = '正文', table = false, foreign = false }, row) => {
    const current = leads.map((leading) => {
      const character = { index: characters.length, leading, pointSize: 10.5 };
      characters.push(character);
      return character;
    });
    current[-1] = current.at(-1);
    return {
      baseline: (row + 1) * 10,
      contents: text,
      characters: current,
      paragraphs: [{ contents: text, appliedParagraphStyle: { name: style }, tables: table ? [{}] : [] }],
      insertionPoints: {
        0: { index: current[0].index, parentTextFrames: [foreign ? { id: 3 } : frame] },
        '-1': { index: current.at(-1).index + 1 },
      },
    };
  });
  const last = frame.lines.at(-1);
  const startingBaseline = last.baseline;
  const document = {
    recompose() {
      last.baseline = startingBaseline + (frame.lines[0].characters[-1].leading - 15) * pointToMm;
    },
  };
  return { document, body, frame, changes, startingBaseline };
}

const guarded = mockFrame([
  {},
  { text: '式\uFFFC', leads: [18, 15] },
  { text: '占\u0016' },
  { table: true },
  { leads: [15.2, 15] },
  { style: '一级标题' },
  {},
  { foreign: true },
  {},
]);
const successful = align(guarded.document, guarded.body, guarded.frame, guarded.startingBaseline + 0.2 * pointToMm, 0.001);
assert.equal(successful.passed, true);
assert.equal(successful.changed, true);
assert.deepEqual(guarded.changes, [{ start: 0, end: 1 }]);
assert.equal(guarded.frame.lines[1].characters[0].leading, 18);
console.log('PASS frame alignment adjusts eligible text and preserves anchors, mixed leading, tables, headings and frame boundaries');

const partial = mockFrame([{}, {}]);
const unsuccessful = align(partial.document, partial.body, partial.frame, partial.startingBaseline + 2 * pointToMm, 0.001);
assert.equal(unsuccessful.passed, false);
assert.ok(unsuccessful.passes > 0);
assert.equal(unsuccessful.changed, false);
assert.equal(unsuccessful.after, partial.startingBaseline);
assert.deepEqual(partial.frame.lines[0].characters.map((character) => character.leading), [15, 15]);
assert.ok(partial.changes.length >= 2);
console.log('PASS frame alignment rolls back accepted intermediate leading when the target is unreachable');
