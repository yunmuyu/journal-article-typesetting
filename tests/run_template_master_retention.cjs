const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const source = fs.readFileSync(path.join(__dirname, '..',
  '2-导入_InDesign', 'initialize_journal_qa_template.jsx'), 'utf8');
const functionSource = source.match(
  /    function removeUnscopedPasteboardStories\(document\) \{[\s\S]*?\n    \}/);
assert.ok(functionSource, 'template cleanup function is available');
const cleanup = vm.runInNewContext(`(${functionSource[0]})`);
const normalPage = { documentOffset: 0, parent: { constructor: { name: 'Spread' } } };
const masterPage = { documentOffset: -1, parent: { constructor: { name: 'MasterSpread' } } };
const pasteboardFrame = { parentPage: null };
const normalFrame = { parentPage: normalPage };
const masterFrame = { parentPage: masterPage };
const groupedMasterFrame = {
  parentPage: masterPage,
  parent: { constructor: { name: 'Group' }, parentPage: masterPage }
};

function documentWithStories(specs) {
  const document = { stories: [] };
  for (const spec of specs) {
    const story = {
      extractLabel: () => spec.role || '',
      textContainers: []
    };
    for (const properties of spec.frames) {
      const frame = {
        ...properties,
        isValid: true,
        remove() {
          this.isValid = false;
          story.textContainers.splice(story.textContainers.indexOf(this), 1);
          if (!story.textContainers.length) {
            document.stories.splice(document.stories.indexOf(story), 1);
          }
        }
      };
      story.textContainers.push(frame);
    }
    document.stories.push(story);
  }
  return document;
}

const retainedCases = [
  { name: 'normal page', frames: [normalFrame] },
  { name: 'master page with negative document offset', frames: [masterFrame] },
  { name: 'grouped text on a master page', frames: [groupedMasterFrame] },
  { name: 'mixed pasteboard and normal page story', frames: [pasteboardFrame, normalFrame] },
  { name: 'mixed pasteboard and master page story', frames: [pasteboardFrame, masterFrame] },
  { name: 'role-tagged pasteboard story', role: 'body', frames: [pasteboardFrame] }
];

for (const spec of retainedCases) {
  test(`retains all text containers when story has ${spec.name}`, () => {
    // Given
    const document = documentWithStories([spec]);
    const story = document.stories[0];
    const frames = story.textContainers.slice();
    // When
    const removed = cleanup(document);
    // Then
    assert.equal(removed, 0);
    assert.deepEqual(document.stories, [story]);
    assert.deepEqual(story.textContainers, frames);
    assert.ok(frames.every(frame => frame.isValid));
  });
}

test('removes every container when unscoped stories are entirely on the pasteboard', () => {
  // Given
  const document = documentWithStories([
    { frames: [pasteboardFrame, pasteboardFrame] },
    { frames: [pasteboardFrame] }
  ]);
  const frames = document.stories.flatMap(story => story.textContainers);
  // When
  const removed = cleanup(document);
  // Then
  assert.equal(removed, 2);
  assert.deepEqual(document.stories, []);
  assert.ok(frames.every(frame => !frame.isValid));
});

test('removes only unscoped pasteboard stories from a mixed document', () => {
  // Given
  const document = documentWithStories([
    { frames: [masterFrame] },
    { frames: [pasteboardFrame] },
    { role: 'footer', frames: [pasteboardFrame] },
    { frames: [normalFrame, pasteboardFrame] }
  ]);
  const retained = [document.stories[0], document.stories[2], document.stories[3]];
  // When
  const removed = cleanup(document);
  // Then
  assert.equal(removed, 1);
  assert.deepEqual(document.stories, retained);
});
