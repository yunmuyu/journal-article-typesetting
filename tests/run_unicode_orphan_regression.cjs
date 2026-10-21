const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const source = fs.readFileSync(path.join(__dirname, '..', '2-导入_InDesign',
  'journal_layout_rules.jsxinc'), 'utf8');
const context = vm.createContext({ Position: { SUPERSCRIPT: 1 } });
vm.runInContext(source, context);
const layout = context.JournalLayout;

function line(text, superscript = '') {
  // InDesign may expose a supplementary character as one or two UTF-16 units.
  const characters = text.split('').map(contents => ({ contents, position: 0 }));
  characters.push(...superscript.split('').map(contents => ({ contents, position: 1 })));
  return { characters: { everyItem: () => ({ getElements: () => characters }) } };
}

for (const [name, text, expected] of [
  ['ordinary Han', '间。', true],
  ['two Han characters', '空间。', false],
  ['Chinese Extension A', '\u3400。', true],
  ['compatibility Han', '\uF900。', true],
  ['Chinese Extension B', '\uD840\uDC00。', true],
  ['Chinese Extension I', '\uD87A\uDFF0。', true],
  ['Chinese Extension J', '\uD888\uDFB0。', true],
  ['two supplementary Han characters', '\uD840\uDC00\uD840\uDC01。', false],
  ['one ordinary and one supplementary Han', '间\uD840\uDC00', false],
  ['variation selector with Han', '间\uFE00。', true],
  ['supplementary variation selector with Han', '间\uDB40\uDD00。', true],
  ['supplementary symbol only', '\uD83D\uDE00。', false],
  ['unpaired high surrogate', '\uD840。', false],
  ['unpaired low surrogate', '\uDC00。', false],
  ['private-use character', '\uE000。', false],
  ['ASCII word', 'abc', false],
  ['empty line', '', false],
  ['control characters around Han', '\t间。\r', true]
]) {
  test(`single-character detection: ${name}`, () => {
    const input = line(text);
    const result = layout.orphanLine(input);
    assert.equal(result, expected);
  });
}

test('superscript references do not hide a supplementary Han orphan', () => {
  const input = line('\uD840\uDC00。', '[4-5]');
  assert.equal(layout.orphanLine(input), true);
});

test('a whole supplementary character in one InDesign Character is counted once', () => {
  const characters = [{ contents: '\uD840\uDC00', position: 0 }];
  const input = { characters: { everyItem: () => ({ getElements: () => characters }) } };
  assert.equal(layout.orphanLine(input), true);
});

test('ordinary BMP results retain the previous decision across representative combinations', () => {
  function previous(text) {
    let chinese = 0, symbols = 0;
    for (const unit of text) {
      const code = unit.charCodeAt(0);
      if (code <= 32) continue;
      if (code >= 19968 && code <= 40959) chinese++;
      else symbols++;
    }
    return chinese === 1 && symbols <= 1;
  }
  const tokens = ['', '中', '文', '。', '，', 'A', '1', ' ', '\t', '\r'];
  for (const a of tokens) for (const b of tokens) for (const c of tokens) {
    const text = a + b + c;
    assert.equal(layout.orphanLine(line(text, '[12]')), previous(text), JSON.stringify(text));
  }
});

test('loading shared rules does not install a global codePointAt polyfill', () => {
  const clean = vm.createContext({ Position: { SUPERSCRIPT: 1 } });
  vm.runInContext('delete String.prototype.codePointAt;', clean);
  vm.runInContext(source, clean);
  assert.equal(vm.runInContext('typeof String.prototype.codePointAt', clean), 'undefined');
});
