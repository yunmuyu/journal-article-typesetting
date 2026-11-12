const test = require('node:test');
const assert = require('node:assert/strict');
const { reuseAdvance } = require('../experimental/offline-layout/measured-advance.cjs');

const previous = { start: 0, end: 4, text: 'ABC\r', baseline: 12 };
const current = { start: 4, end: 8, text: 'DEF\r', baseline: 18 };
const compositionKey = 'verified input composition';
const measured = { lines: [previous, current], compositionKey, widthMm: 85.5 };

test('reuses a measured advance when the same line pair translates', () => {
  const target = { ...measured, lines: [
    { ...previous, baseline: 112 }, { ...current, baseline: 118 },
  ] };
  assert.equal(reuseAdvance(measured, target), 6);
});

test('rejects a pair when a line break moves', () => {
  const target = { ...measured, lines: [
    { ...previous, end: 5, text: 'ABC\rD' }, { ...current, start: 5, text: 'EF\r' },
  ] };
  assert.equal(reuseAdvance(measured, target), null);
});

test('rejects a pair when width changes', () => {
  assert.equal(reuseAdvance(measured, { ...measured, widthMm: 85.4 }), null);
});

test('rejects a pair when composition changes', () => {
  assert.equal(reuseAdvance(measured, { ...measured, compositionKey: 'different inputs' }), null);
});

test('rejects a pair when the incoming line becomes a column start', () => {
  assert.equal(reuseAdvance(measured, { ...measured, columnStart: true }), null);
});


test('rejects table content, malformed pairs, and nonpositive baseline advance', () => {
  assert.equal(reuseAdvance(measured, { ...measured, lines: [previous] }), null);
  assert.equal(reuseAdvance(measured, { ...measured, lines: [previous, { ...current, hasTable: true }] }), null);
  assert.equal(reuseAdvance({ ...measured, lines: [previous, { ...current, baseline: NaN }] }, measured), null);
  assert.equal(reuseAdvance({ ...measured, lines: [previous, { ...current, baseline: 12 }] }, measured), null);
});
