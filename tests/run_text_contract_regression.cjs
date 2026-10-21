const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..', '2-导入_InDesign');
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(root, 'journal_frontmatter.jsxinc'), 'utf8'), context);
vm.runInContext(fs.readFileSync(path.join(root, 'journal_layout_rules.jsxinc'), 'utf8'), context);
const front = context.JournalFrontmatter;
const layout = context.JournalLayout;

const text = '中图分类号：TP311.1  文献标识码：A  文章编号：2096-4706（2026）00-0000-00';
const expected = text.replace('  文献', '\t文献').replace('  文章', '\t文章');
assert.equal(front.classificationPlan(text).text, expected);
assert.equal(front.classificationPlan(expected).edits.length, 0, 'idempotent tabs');
assert.equal(front.classificationPlan(text.replace(/  /g, '')).text, expected);
assert.equal(front.classificationPlan(text.replace(/  /g, '　 ')).text, expected);
assert.equal(front.classificationPlan(text).text.replace(/\t/g, ''), text.replace(/  /g, ''), 'preserve semantic content');
assert.deepEqual(JSON.parse(JSON.stringify(front.classificationPlan(text).edits)).map(e => e.before), ['  ', '  ']);

assert.equal(layout.specialGlyphFont('､'), '思源宋体 CN');
assert.equal(layout.specialGlyphFont('，'), null, 'do not replace source punctuation');
assert.equal(layout.specialGlyphFont('A'), null, 'no global fallback');
assert.equal(layout.glyphFontIssue('､', '现 宋体-1'), '思源宋体 CN');
assert.equal(layout.glyphFontIssue('､', '思源宋体 CN'), null);
assert.equal(layout.glyphFontIssue('，', '现 宋体-1'), null);
console.log('PASS classification tabs and required glyph fallback');
