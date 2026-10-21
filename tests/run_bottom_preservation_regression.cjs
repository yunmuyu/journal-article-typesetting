const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const context = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '..',
  '2-导入_InDesign', 'journal_bottom_plan.jsxinc'), 'utf8'), context);
const apply = context.JournalBottomPlan.apply;

function collection(items) {
  items[-1] = items[items.length - 1];
  items.item = index => items[index < 0 ? items.length + index : index];
  items.itemByID = id => items.find(item => item.id === id) || { isValid: false };
  items.everyItem = () => ({ getElements: () => items.slice() });
  return items;
}

function fixture(mode = 'stable') {
  const writes = [];
  const leading = Array.from({ length: 40 }, (_, index) =>
    index >= 30 ? 15.1 : index >= 15 && index < 20 ? 15.05 : 15);
  const characters = collection(leading.map((_, index) => ({
    index,
    get leading() { return leading[index]; },
    set leading(value) { writes.push({ index, value }); leading[index] = value; }
  })));
  characters.itemByRange = (start, end) => {
    const selected = characters.slice(start, end + 1);
    return {
      isValid: true,
      getElements() { return selected.slice(); },
      get leading() { return selected[0].leading; },
      set leading(value) { selected.forEach(character => { character.leading = value; }); }
    };
  };
  const frames = collection([
    { id: 101, isValid: true, parentPage: { id: 201, documentOffset: 0 } },
    { id: 102, isValid: true, parentPage: { id: 201, documentOffset: 0 } }
  ]);
  const cellText = { lines: collection([]), parentTextFrames: [] };
  const row = { cells: collection([{ texts: [cellText], rowSpan: 1 }]) };
  const table = { label: 'source-table-1', rows: collection([row]) };
  const story = {
    id: 81, isValid: true, overflows: false,
    extractLabel: () => 'body', characters, textContainers: frames,
    tables: collection([table])
  };
  frames.forEach(frame => { frame.parentStory = story; });
  function line(frame, start, end) {
    return {
      insertionPoints: collection([
        { index: start, parentTextFrames: [frame] },
        { index: end, parentTextFrames: [frame] }
      ]),
      characters: collection(characters.slice(start, end)),
      parentTextFrames: [frame]
    };
  }
  function compose() {
    const adjusted = leading[10] > 15.1;
    const split = mode === 'endpoint-drift' && adjusted ? 21 : 20;
    frames[0].lines = collection([line(frames[0], 0, 10), line(frames[0], 10, split)]);
    frames[1].lines = collection([line(frames[1], split, 30), line(frames[1], 30, 40)]);
    for (const frame of frames) {
      frame.insertionPoints = collection([
        frame.lines[0].insertionPoints[0], frame.lines[-1].insertionPoints[-1]
      ]);
    }
    const tableFrame = mode === 'table-drift' && adjusted ? frames[1] : frames[0];
    cellText.lines = collection([line(tableFrame, 5, 6)]);
    cellText.parentTextFrames = [tableFrame];
  }
  compose();
  const document = {
    id: 71, stories: collection([story]), textFrames: frames,
    pageItems: frames, allPageItems: frames,
    recomposeCount: 0,
    recompose() { this.recomposeCount++; compose(); }
  };
  const plan = {
    status: 'ready', blankSpaceAllowed: false,
    preservation: {
      required: true, documentId: 71, storyId: 81,
      frames: [
        { id: 101, endpoint: [0, 20], lineCount: 2 },
        { id: 102, endpoint: [20, 40], lineCount: 2 }
      ],
      tables: [{ label: 'source-table-1', rows: [{ rowIndex: 0, frameId: 101 }] }]
    },
    columns: [{ adjustments: [
      { kind: 'leading', id: 'first-range', role: 'body', toPt: 15.2,
        target: { storyRole: 'body', startIndex: 10, endIndex: 19 } },
      { kind: 'leading', id: 'second-range', role: 'body', toPt: 15.3,
        target: { storyRole: 'body', startIndex: 30, endIndex: 39 } }
    ] }]
  };
  return { document, story, frames, cellText, plan, writes, leading };
}

function flow(input) {
  return {
    frames: input.frames.map(frame => ({
      id: frame.id, lineCount: frame.lines.length,
      endpoint: [frame.lines[0].insertionPoints[0].index,
        frame.lines[-1].insertionPoints[-1].index]
    })),
    rowFrame: input.cellText.lines[0].insertionPoints[0].parentTextFrames[0].id
  };
}

const preconditions = [
  { name: 'document identity differs', change(input) { input.document.id = 72; } },
  { name: 'story identity differs', change(input) { input.story.id = 82; } },
  { name: 'initial frame endpoint differs',
    change(input) { input.plan.preservation.frames[0].endpoint[1] = 19; } },
  { name: 'initial frame line count differs',
    change(input) { input.plan.preservation.frames[0].lineCount = 3; } },
  { name: 'initial table row belongs to another frame',
    change(input) { input.plan.preservation.tables[0].rows[0].frameId = 102; } }
];

for (const scenario of preconditions) {
  test(`rejects without writes when ${scenario.name}`, () => {
    const input = fixture();
    const before = input.leading.slice();
    scenario.change(input);
    assert.throws(() => apply(input.document, input.plan), /^Error: BOTTOM_/);
    assert.deepEqual(input.writes, []);
    assert.deepEqual(input.leading, before);
    assert.equal(input.document.recomposeCount, 0);
  });
}

for (const mode of ['endpoint-drift', 'table-drift']) {
  test(`restores all leading and original flow before throwing on ${mode}`, () => {
    const input = fixture(mode);
    const beforeLeading = input.leading.slice();
    const beforeFlow = flow(input);
    assert.throws(() => apply(input.document, input.plan), /^Error: BOTTOM_/);
    assert.ok(input.writes.some(write => write.value === 15.2));
    assert.ok(input.writes.some(write => write.value === 15.3));
    assert.deepEqual(input.leading, beforeLeading);
    assert.deepEqual(flow(input), beforeFlow);
    assert.equal(input.document.recomposeCount, 2);
  });
}

test('applies valid leading changes with exactly one recompose', () => {
  const input = fixture();
  const beforeFlow = flow(input);
  const result = apply(input.document, input.plan);
  assert.equal(result.applied, 2);
  assert.equal(result.recomposes, 1);
  assert.equal(input.document.recomposeCount, 1);
  assert.ok(input.leading.slice(10, 20).every(value => value === 15.2));
  assert.ok(input.leading.slice(30, 40).every(value => value === 15.3));
  assert.deepEqual(flow(input), beforeFlow);
});
