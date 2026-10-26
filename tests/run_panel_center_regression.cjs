const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const context = vm.createContext({
  LinkStatus: { NORMAL: 'normal' },
  PageSideOptions: { LEFT_HAND: 'left', RIGHT_HAND: 'right' }
});
vm.runInContext(fs.readFileSync(path.join(__dirname, '..',
  '2-导入_InDesign', 'journal_layout_rules.jsxinc'), 'utf8'), context);
const layout = context.JournalLayout;
const layouts = [
  { name: '2x3 left', side: 'left', left: 14.5, columns: 3,
    centers: [44.166666666667, 103.5, 162.833333333333, 44.166666666667, 103.5, 162.833333333333] },
  { name: '2x3 right', side: 'right', left: 17.5, columns: 3,
    centers: [47.166666666667, 106.5, 165.833333333333, 47.166666666667, 106.5, 165.833333333333] },
  { name: '1x2 left', side: 'left', left: 14.5, columns: 2, centers: [59, 148] },
  { name: '1x2 right', side: 'right', left: 17.5, columns: 2, centers: [62, 151] }
];

function fixture(spec) {
  const page = { side: spec.side, documentOffset: 4 };
  const numbers = spec.centers.map((_, index) => index + 11);
  const graphics = spec.centers.map((center, index) => ({
    itemLink: { name: `figure-${numbers[index]}.pdf`, status: 'normal' },
    parent: {
      label: `source-figure-${numbers[index]}`,
      geometricBounds: [40 + Math.floor(index / spec.columns) * 30, center - 20,
        60 + Math.floor(index / spec.columns) * 30, center + 20],
      parentPage: page
    }
  }));
  const story = role => ({
    extractLabel: () => role, paragraphs: [], textContainers: [], tables: []
  });
  return {
    document: {
      recompose() {},
      pages: [page], spreads: [{ pages: [page] }],
      stories: [story('body'), {...story('front'), textContainers:[{parentPage:page,lines:[{baseline:50}]}]}, {...story('footer'), textContainers:[{parentPage:page,lines:[{baseline:100}]}]}],
      allGraphics: graphics, allPageItems: [], allParagraphStyles: [],
      compositeFonts: { itemByName: () => ({ isValid: false }) }
    },
    config: {
      startOnLeft: false, fixedFrames: [], figureCount: 0,
      graphicCount: graphics.length, tableCount: 0,
      figurePanels: [{ numbers, columns: spec.columns, pageIndex: 4 }]
    }
  };
}

test('panel fixture supplies the front frame required by the full audit', () => {
  const input = fixture(layouts[0]);
  const front = input.document.stories.find(story => story.extractLabel() === 'front');
  assert.equal(front.textContainers[0].parentPage, input.document.pages[0]);
  const result = layout.audit(input.document, input.config);
  assert.ok(Array.from(result.errors).some(error => error.code === 'GUIDE_COUNT'),
    'unrelated audit checks remain active');
});

function figureErrors(input) {
  // Empty story fixtures isolate figure geometry; font/guide/preview checks stay active.
  return Array.from(layout.audit(input.document, input.config).errors)
    .filter(error => error.code === 'FIGURE_CENTER' || error.code === 'FIGURE_PANEL_PAGE');
}

for (const spec of layouts) {
  test(`accepts centered panels when layout is ${spec.name}`, () => {
    // Given
    const input = fixture(spec);
    // When
    const errors = figureErrors(input);
    // Then
    assert.deepEqual(errors, []);
  });

  test(`computes column centers when layout is ${spec.name}`, () => {
    // Given / When
    const centers = spec.centers.map((_, index) =>
      layout.figurePanelCenter(spec.left, index, spec.columns));
    // Then
    centers.forEach((actual, index) =>
      assert.ok(Math.abs(actual - spec.centers[index]) < 1e-10));
  });
}

for (const spec of layouts.slice(0, 2)) {
  test(`detects actual second-row offset when layout is ${spec.name}`, () => {
    // Given
    const input = fixture(spec);
    const frame = input.document.allGraphics[4].parent;
    frame.geometricBounds[1] += 0.05;
    frame.geometricBounds[3] += 0.05;
    // When
    const errors = figureErrors(input);
    // Then
    assert.equal(errors.length, 1);
    assert.equal(errors[0].code, 'FIGURE_CENTER');
    assert.ok(errors[0].detail.startsWith('figure-15.pdf '));
  });

  test(`detects wrong page despite correct center when layout is ${spec.name}`, () => {
    // Given
    const input = fixture(spec);
    const frame = input.document.allGraphics[4].parent;
    frame.parentPage = { side: spec.side, documentOffset: 5 };
    // When
    const errors = figureErrors(input);
    // Then
    assert.equal(errors.length, 1);
    assert.equal(errors[0].code, 'FIGURE_PANEL_PAGE');
    assert.equal(errors[0].detail, 'figure-15.pdf');
  });
}
