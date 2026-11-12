const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.join(__dirname, '../2-导入_InDesign');
const importer = fs.readFileSync(path.join(root, 'import_word_article_to_indesign.jsx'), 'utf8').replace(/^#target[^\r\n]*[\r\n]*/, '');
const page = {id: 1, documentOffset: 0, side: 'left'};
const body = {id: 2, textContainers: [{parentPage: page}]};
const doc = {id: 3, isValid: true, pages: {itemByID: () => page}, stories: {itemByID: () => body}, allPageItems: []};
const scope = {articleId: 'second', documentId: 3, pageIds: [1], bindings: [{id: 2, role: 'body'}]};
// Given: B's valid scope but an insertion point from another article.
const request = {document: doc, articleScope: scope, target: {isValid: true, parentStory: {id: 9, parent: doc}}, data: {blocks: [{role: 'body', text: 'second article'}]}};
const app = {get scriptPreferences() { throw Error('IMPORT_STARTED_BEFORE_SCOPE_VALIDATION'); }};
const context = vm.createContext({PageSideOptions: {LEFT_HAND: 'left'}, JournalImportRequest: request, app});
vm.runInContext(fs.readFileSync(path.join(root, 'journal_article_scope.jsxinc'), 'utf8'), context);
// When / Then: the actual public importer must reject before touching native formatting.
assert.throws(() => vm.runInContext(importer, context), /ARTICLE_TARGET_NOT_BODY/);
context.JournalArticleScope = undefined;
assert.throws(() => vm.runInContext(importer, context), /ARTICLE_SCOPE_MODULE_REQUIRED/);
console.log('PASS public importer rejects a different article target before native mutations');
