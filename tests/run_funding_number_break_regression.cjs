const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = path.join(__dirname, '../2-导入_InDesign/journal_layout_rules.jsxinc');
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(source, 'utf8'), context);

const { protectedTokens } = context.JournalLayout;
const funding = protectedTokens({ contents: '项目编号 [2022]123' }, 'fund');
const bracketedYear = funding.find(token => token.text === '[2022]');
assert.equal(bracketedYear.start, 5);
assert.equal(bracketedYear.end, 10);

const body = protectedTokens({ contents: '正文[2]' }, 'body');
assert.equal(body.find(token => token.text === '[2]').start, 1);
