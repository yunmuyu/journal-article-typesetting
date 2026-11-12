const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const context = vm.createContext({PageSideOptions: {LEFT_HAND: 'left'}});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../2-导入_InDesign/journal_article_scope.jsxinc'), 'utf8'), context);
const api = context.JournalArticleScope;
function collection(items) { items.itemByID = id => items.find(item => item.id === id) || {isValid: false}; return items; }
// Given: two articles share slot labels but have separate native identities.
const pages = collection([{id: 10, documentOffset: 0, side: 'left'}, {id: 11, documentOffset: 1, side: 'right'}, {id: 20, documentOffset: 2, side: 'left'}]);
const frameA = {id: 100, parentPage: pages[0], label: 'body-left'};
const frameB = {id: 200, parentPage: pages[2], label: 'body-left'};
const storyA = {id: 101, isValid: true, textContainers: [frameA]};
const storyB = {id: 201, isValid: true, textContainers: [frameB]};
frameA.parentStory = storyA; frameB.parentStory = storyB;
const document = {id: 1, pages, stories: collection([storyA, storyB]), allPageItems: [frameA, frameB]};
const spec = {articleId: 'B', documentId: 1, pageIds: [20], bindings: [{id: 201, role: 'body'}], slots: {'body-left': 200}};
// When: resolve B through explicit identities.
const result = api.resolve(document, spec);
// Then: equal labels do not select A; invalid or cross-boundary identities fail before writes.
assert.equal(result.body, storyB);
assert.equal(result.slots['body-left'], frameB);
assert.throws(() => api.resolve(document, {...spec, documentId: 2}), /ARTICLE_DOCUMENT_CHANGED/);
assert.throws(() => api.resolve(document, {...spec, slots: {'body-left': 100}}), /ARTICLE_SLOT_OUTSIDE_SCOPE/);
assert.throws(() => api.resolve(document, {...spec, bindings: [{id: 999, role: 'body'}]}), /ARTICLE_STORY_MISSING/);
assert.throws(() => api.resolve(document, {...spec, bindings: [{id: 201, role: 'body'}, {id: 201, role: 'front'}]}), /ARTICLE_STORY_DUPLICATE/);
assert.throws(() => api.resolve(document, {...spec, pageIds: [20, 10]}), /ARTICLE_PAGE_ORDER/);
storyB.textContainers.push({id: 202, parentPage: pages[1]});
assert.throws(() => api.resolve(document, spec), /ARTICLE_STORY_OUTSIDE_SCOPE/);
storyB.textContainers.pop();
assert.equal(storyA.textContainers[0], frameA);
console.log('PASS explicit article identities, duplicate labels, stale identities and cross-boundary story rejection');
