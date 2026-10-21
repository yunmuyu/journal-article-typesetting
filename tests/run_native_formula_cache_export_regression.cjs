const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../2-导入_InDesign/journal_formula_native_cache.jsx'), 'utf8');
for (const action of ['paste-and-cache', 'reuse-idms']) for (const nativeType of ['Group', 'Polygon']) {
  const events = [], labels = {}, point = {}, job = {action, number: 1, documentName: 'test_QA.indd', markerText: 'FORMULA', idmsPath: 'formula.idms'};
  let exists = action === 'reuse-idms', anchored = false;
  const group = {constructor: {name: 'Group'}, allGraphics: [], absoluteHorizontalScale: 100, absoluteVerticalScale: 100,
    geometricBounds: [0, 0, 10, 30], getElements() {return [this];},
    insertLabel(key, value) {labels[key] = value;},
    exportFile(format) {assert.equal(anchored, false, 'IDMS must export before anchoring'); assert.equal(labels['formula-native-paste'], 'true'); events.push('export'); exists = true;},
    anchoredObjectSettings: {insertAnchoredObject(actual) {assert.equal(actual, point); anchored = true; events.push('anchor');}}};
  const pasted = nativeType === 'Group' ? group : {...group, constructor: {name: 'Polygon'}};
  const container = {getElements() {return [this];}};
  let boundsAdded = 0;
  const story = {contents: 'FORMULA', insertionPoints: [point], getElements() {return [this];}, characters: {itemByRange() {return {remove() {story.contents = '';}};}}};
  const doc = {id: 1, isValid: true, stories: [story], windows: [{}], layoutWindows: [{}], recompose() {}, pages: [{place() {events.push('place'); return [group];}}]};
  pasted.parent = doc;
  doc.swatches = {itemByName: name => name};
  doc.rectangles = {add(properties) {assert.deepEqual(Array.from(properties.geometricBounds), [0, 0, 10, 30]); boundsAdded++; return container;}};
  doc.groups = {add(items) {assert.equal(items[0], pasted); assert.equal(items[1], container); assert.equal(container.nonprinting, true); assert.equal(container.label, 'formula-native-bounds'); return group;}};
  const app = {activeDocument: doc, documents: {itemByName: () => ({getElements: () => [doc]})}, clipboardPreferences: {preferPDFWhenPasting: true}, selection: [], select() {}, paste() {events.push('paste'); this.selection = [pasted];}};
  const result = vm.runInNewContext(source, {JournalFormulaNativeCacheJob: job, app, File: () => ({get exists() {return exists;}}), NothingEnum: {NOTHING: 0}, AnchorPosition: {INLINE_POSITION: 1}, ExportFormat: {INDESIGN_SNIPPET: 2}});
  assert.equal(result, action + '\t1\t30\t10\t0');
  assert.deepEqual(events, action === 'paste-and-cache' ? ['paste', 'export', 'anchor'] : ['place', 'anchor']);
  assert.equal(app.clipboardPreferences.preferPDFWhenPasting, true);
  assert.equal(group.label, 'source-formula-1');
  assert.equal(boundsAdded, action === 'paste-and-cache' && nativeType === 'Polygon' ? 1 : 0);
}
console.log('PASS native cache wraps single native vectors in nonprinting bounds and exports detached groups before anchoring; reuse anchors native IDMS; clipboard preference restored');
