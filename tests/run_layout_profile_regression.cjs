const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {fromApproved} = require('../2-导入_InDesign/journal_layout_profile.cjs');
const baseline = {
  objects: [{label: 'source-figure-1', bounds: [20, 10, 40, 50], links: [{path: 'F:\\figures\\original.pdf'}]}],
  stories: [{role: 'body', paragraphs: [
    {text: '图1  波形\r', style: '图注/表名'},
    {text: '完整分析段，如图1所示。\r', style: '正文'},
    {text: '\t（1）\r', style: '公式', ranges: [{leading: 22.5}]}
  ], tables: [{label: 'source-table-1', rows: 2, widths: [30, 55.5], cells: [
    {row: 0, rowSpan: 1, height: 4.8}, {row: 0, rowSpan: 1, height: 4.8},
    {row: 1, rowSpan: 1, height: 12.6}
  ]}]}]
};
const job = {assets: [{kind: 'figure', number: 1, width: 20, height: 10, path: 'F:/figures/original.pdf'}],
  figures: [{mode: 'inline', number: 1}], tables: [{number: 1}]};
const blocks = [{role: 'body', text: '完整分析段，如图1所示。'}, {role: 'figure_caption', text: '图1  波形'}];
const profile = fromApproved(baseline, job, blocks);
assert.deepEqual(profile.figures[0], {number: 1, path: job.assets[0].path, width: 40, height: 20});
assert.deepEqual(profile.tables[0].minimumHeightsMm, [4.8, 5], 'multiline rows must grow naturally');
assert.deepEqual(profile.placements, [{number: 1, beforeParagraphText: blocks[0].text}]);
assert.deepEqual(profile.formulas, [{number: 1, leadingPt: 22.5}]);
assert.equal(fromApproved(baseline, job, blocks.toReversed()).placements.length, 0);
const wrong = structuredClone(baseline); wrong.objects[0].links[0].path = 'F:/other.pdf';
assert.throws(() => fromApproved(wrong, job, blocks), /PROFILE_FIGURE_SOURCE/);
wrong.objects[0].links[0].path = job.assets[0].path; wrong.objects[0].bounds[3] = 60;
assert.throws(() => fromApproved(wrong, job, blocks), /PROFILE_FIGURE_ASPECT/);
assert.throws(() => fromApproved(baseline, job, [blocks[0], ...blocks]), /PROFILE_REFERENCE/);

const collection = items => Object.assign(items, {everyItem: () => ({getElements: () => items})});
let resizes = 0;
const figure = {label: 'source-figure-1', geometricBounds: [0, 0, 10, 20],
  allGraphics: [{itemLink: {filePath: job.assets[0].path},geometricBounds:[0,0,10,20]}],
  fit() { this.allGraphics[0].geometricBounds=this.geometricBounds.slice(); },
  resize(_space, _anchor, _method, ratios) {
    resizes++;
    this.geometricBounds[2] *= ratios[0]; this.geometricBounds[3] *= ratios[1];
  }};
const body = {paragraphs: collection([{contents: '正文\r', startParagraph: 0}]), tables: collection([]), overflows: false};
const d = {allPageItems: [figure], recompose() {}};
const ctx = vm.createContext({CoordinateSpaces: {PASTEBOARD_COORDINATES: 1}, AnchorPoint: {CENTER_ANCHOR: 1},
  ResizeMethods: {MULTIPLYING_CURRENT_DIMENSIONS_BY: 1},FitOptions:{PROPORTIONALLY:1,CENTER_CONTENT:2}});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../2-导入_InDesign/journal_layout_profile.jsxinc'), 'utf8'), ctx);
const p = {schemaVersion: 1, figures: profile.figures, tables: [], placements: [], formulas: []};
ctx.JournalLayoutProfile.apply(d, body, p, () => []);
assert.deepEqual(figure.geometricBounds, [0, 0, 20, 40]);
assert.deepEqual(figure.allGraphics[0].geometricBounds,figure.geometricBounds,'resizing the frame must also fit its complete source graphic');
ctx.JournalLayoutProfile.apply(d, body, p, () => []);
assert.equal(resizes, 1, 'repeating an applied profile must not scale again');
const bigger = structuredClone(p); bigger.figures[0].width = 80; bigger.figures[0].height = 40;
assert.throws(() => ctx.JournalLayoutProfile.apply(d, body, bigger, () => { throw Error('panel capacity'); }), /panel capacity/);
assert.deepEqual(figure.geometricBounds, [0, 0, 20, 40], 'failed layout restores the original figure');
assert.deepEqual(figure.allGraphics[0].geometricBounds,figure.geometricBounds,'failed layout also restores the graphic transform');
const indexedParagraphs = collection([
  {contents: '目标段落\r', index: 0, insertionPoints: [{index: 0}]},
  {contents: '\uFFFC\r', index: 40, insertionPoints: [{index: 40}]},
  {contents: '\r', index: 42, insertionPoints: [{index: 42}]},
  {contents: '图1  波形\r', index: 43, insertionPoints: [{index: 43}]},
  {contents: '原后续段落\r', index: 54, insertionPoints: [{index: 54}]}
]);
const indexedBody = {id: 7, paragraphs: indexedParagraphs, tables: collection([])};
const inlineFigure = {label: 'source-figure-1', parent: {parentStory: indexedBody, paragraphs: [indexedParagraphs[1]]}};
const validated = ctx.JournalLayoutProfile.validate({allPageItems: [inlineFigure]}, indexedBody,
  {schemaVersion: 1, figures: [], tables: [], formulas: [], placements: [{number: 1, beforeParagraphText: '目标段落\r'}]});
assert.equal(validated.placements[0].originalNext, '原后续段落\r', 'InDesign Paragraph.index is a character offset, not a paragraph ordinal');
console.log('PASS approved size/source, semantic placement, natural row growth, formula leading, idempotency, failed-panel rollback');
