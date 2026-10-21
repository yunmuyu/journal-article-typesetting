const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../2-导入_InDesign/journal_article_assembly.jsxinc'), 'utf8');
const body = source.slice(source.indexOf('    function formula('), source.indexOf('    function frontEntries('));
for (const printed of [null, '7']) {
  let oldValid = true, text = 'marker', insertedAt;
  const fresh = {insertionPoints: [{index: 40}, {index: 41}], applyParagraphStyle() {assert.equal(oldValid, false);}};
  const story = {getElements() {return [this];}, insertionPoints: {40: {paragraphs: [fresh]}}};
  const stale = {parentStory: story, insertionPoints: [{index: 40}],
    set contents(value) {text = value; oldValid = false;},
    applyParagraphStyle() {throw Error('OLD_PARAGRAPH_INVALID_AFTER_REPLACEMENT');}};
  const group = {geometricBounds: [0, 0, 3, 4], labels: {}, insertLabel(key, value) {this.labels[key] = value;}};
  const context = {printedFormulaNumber: () => printed, style: () => ({}),
    Justification: {LEFT_ALIGN: 'left', CENTER_ALIGN: 'center'},
    insertNativeFormula(d, point) {insertedAt = point.index; return group;},
    fail(code) {throw Error(code);}};
  vm.createContext(context);
  vm.runInContext(body + '\nthis.testFormula=formula;', context);
  context.testFormula({}, stale, 1, {formulas: {mode: 'native-idms'}}, null, 'marker');
  assert.equal(insertedAt, printed === null ? 40 : 41);
  assert.equal(text, printed === null ? '\r' : '\t\t（7）\r');
  assert.equal(group.labels['formula-display'], printed === null ? 'unnumbered' : 'true');
  if (printed === null) assert.equal(fresh.justification, 'center');
}
console.log('PASS display formulas reacquire paragraph after contents replacement, preserving numbered and unnumbered insertion offsets');
