const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const context = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '..',
  '2-导入_InDesign', 'journal_layout_rules.jsxinc'), 'utf8'), context);
const layout = context.JournalLayout;

function fixture() {
  const expected = [{
    masterName: 'A-合成主页', pageIndex: 1,
    bounds: [20, 17.5, 25, 195.5], text: '合成期刊页眉\r'
  }];
  const frame = {
    constructor: {name: 'TextFrame'}, geometricBounds: [20, 17.5, 25, 195.5],
    contents: '合成期刊页眉\r', nonprinting: false
  };
  const frames = [
    { constructor: {name: 'TextFrame'}, geometricBounds: [270, 100, 275, 110], contents: '页码', nonprinting: false },
    frame
  ];
  const master = { isValid: true, pages: [{ allPageItems: [] }, { allPageItems: frames }] };
  const document = {
    masterSpreads: {
      itemByName(name) {
        return name === 'A-合成主页' ? master : { isValid: false };
      }
    }
  };
  return { document, expected, master, frames, frame };
}

test('accepts matching printable master text on the requested page', () => {
  const input = fixture();
  const issues = layout.masterTextIssues(input.document, input.expected);
  assert.equal(issues.length, 0);
});

test('accepts frame coordinates within the matching tolerance', () => {
  const input = fixture();
  input.frame.geometricBounds = [20.01, 17.49, 25.01, 195.49];
  const issues = layout.masterTextIssues(input.document, input.expected);
  assert.equal(issues.length, 0);
});

const rejectedCases = [
  {
    name: 'the named master is missing',
    change(input) { input.expected[0].masterName = 'B-不存在'; }
  },
  {
    name: 'the requested page of the master is missing',
    change(input) { input.master.pages.pop(); }
  },
  {
    name: 'the expected text frame is missing',
    change(input) { input.frames.pop(); }
  },
  {
    name: 'the expected text frame moved outside the coordinate tolerance',
    change(input) { input.frame.geometricBounds[1] += 0.03; }
  },
  {
    name: 'two text frames occupy the expected position',
    change(input) {
      input.frames.push({ ...input.frame, geometricBounds: input.frame.geometricBounds.slice() });
    }
  },
  {
    name: 'the frame text has changed',
    change(input) { input.frame.contents = '变化后的页眉\r'; }
  },
  {
    name: 'the matching text frame is nonprinting',
    change(input) { input.frame.nonprinting = true; }
  }
];

for (const scenario of rejectedCases) {
  test(`reports an issue when ${scenario.name}`, () => {
    const input = fixture();
    scenario.change(input);
    const issues = layout.masterTextIssues(input.document, input.expected);
    assert.equal(issues.length, 1);
    assert.equal(typeof issues[0], 'string');
    assert.ok(issues[0].length > 0);
  });
}
