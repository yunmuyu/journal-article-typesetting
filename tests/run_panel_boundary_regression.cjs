const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../2-导入_InDesign/journal_article_assembly.jsxinc'), 'utf8');
const seamIndex = source.lastIndexOf('    return {');
const seam = seamIndex < 0 ? null : source.slice(seamIndex, source.indexOf('}', seamIndex));
assert.ok(seam, 'assembly export seam');
const context = {
  StartParagraph: {NEXT_PAGE: 'next-page', ANYWHERE: 'anywhere', NEXT_COLUMN: 'next-column'},
  PageSideOptions: {LEFT_HAND: 'left'},
  FitOptions: {FRAME_TO_CONTENT: 1, PROPORTIONALLY: 2},
  AnchorPosition: {ABOVE_LINE: 1}, HorizontalAlignment: {CENTER_ALIGN: 1},
  PDFCrop: {CROP_MEDIA: 1}, File: value => value,
  app: {pdfPlacePreferences: {}},
  __captionBlock(d, paragraph, asset) {
    const frame = paragraph.frame;
    frame.geometricBounds[2] = frame.geometricBounds[0] + asset.height + 5;
  }
};
vm.createContext(context);
vm.runInContext(source.replace(seam,
  '    captionBlock=__captionBlock;\n    return {placePanel:placePanel,refreshPanels:refreshPanels,placeFigure:placeFigure,footerEntries:footerEntries,' + seam.slice('    return {'.length)) , context);
const assembly = context.JournalArticleAssembly;
function deferred(value) {
  return new Proxy({}, {get(target, key) {
    if (key === 'getElements') return () => [value];
    throw Error('Unresolved object specifier: ' + String(key));
  }});
}
let id = 100;
function fixture() {
  const frames = [], page = {id: ++id, documentOffset: 2, side: 'left'};
  page.textFrames = {add(properties) {
    const frame = {id: ++id, parentPage: page, geometricBounds: [...properties.geometricBounds],
      paragraphs: [], parentStory: {id: ++id, insertLabel() {}}, fit() {}};
    frame.paragraphs.push({frame}); frames.push(frame);
    return deferred(frame);
  }};
  const columns = [0, 92.5].map(x => ({id: ++id, parentPage: page, geometricBounds: [26, 14.5 + x, 265, 100 + x]}));
  const marker = {contents: 'JOURNAL_PANEL_0\r', insertionPoints: [{parentTextFrames: [{parentPage: deferred(page)}]}]};
  marker.characters = {length: marker.contents.length, itemByRange() {return {remove() {marker.contents = '\r';}}}};
  const following = {contents: 'following paragraph\r', startParagraph: 'old'};
  const body = {paragraphs: [marker, following], textContainers: columns.map(value => ({parentPage: page, getElements: () => [value]}))};
  return {page, frames, columns, marker, following, body, d: {recompose() {}, allPageItems: frames}};
}
const geometry = {leftPageLeftMm: 14.5, rightPageLeftMm: 17.5, spreadWidthMm: 178, bodyTopMm: 26};
const job = {templateContract: {geometry}, assets: [{kind: 'figure', number: 1, height: 50}]};
for (const keep of [true, false]) {
  const f = fixture(), bindings = [];
  const result = assembly.placePanel(f.d, f.body, {numbers: [1], columns: 1, pageTop: true, keepFollowingAfterPanel: keep}, 0, {1: '图1 Caption'}, job, bindings);
  assert.equal(f.following.startParagraph, keep ? 'next-page' : 'anywhere');
  assert.equal(f.marker.startParagraph, 'anywhere');
  assert.equal(f.marker.contents, '\r');
  assert.equal(f.columns[0].geometricBounds[0], 85);
  assert.equal(f.frames[0].geometricBounds[0], 26);
  assert.equal(result.pageId, f.page.id);
  assert.deepEqual(Array.from(result.frameIds), [f.frames[0].id]);
  assert.equal(bindings.length, 1);
}

const placed = {anchoredObjectSettings: {insertAnchoredObject(point) {this.point = point;}}, place(file) {this.file = file;}, fit() {}};
{
  context.NothingEnum = {NOTHING: null};
  const first = fixture(), next = fixture(), removed = [];
  first.body.contents = 'unchanged source story';
  next.columns[0].isValid = true;
  first.columns[1].nextTextFrame = next.columns[0];
  first.following.insertionPoints = [{parentTextFrames: [next.columns[0]]}];
  const add = first.page.textFrames.add;
  first.page.textFrames.add = properties => {
    const deferredFrame = add(properties), frame = deferredFrame.getElements()[0];
    frame.remove = () => {removed.push(frame.id);first.frames.splice(first.frames.indexOf(frame), 1);};
    frame.getElements = () => [frame];
    return frame;
  };
  Object.defineProperty(first.d, 'allPageItems', {get:()=>[...first.columns,...next.columns,...first.frames,...next.frames]});
  first.d.recompose = () => {
    if (first.marker.startParagraph === 'next-page') {
      first.marker.insertionPoints[0].parentTextFrames = [{id:next.columns[1].id,parentPage:deferred(next.page)}];
      first.body.textContainers = next.body.textContainers;
    } else if (!first.marker.insertionPoints[0].parentTextFrames[0].id) {
      first.marker.insertionPoints[0].parentTextFrames = [{id:first.columns[1].id,parentPage:deferred(first.page)}];
    }
  };
  const spec = {numbers:[1],columns:1,pageTop:false};
  const result = assembly.placePanel(first.d, first.body, spec, 0, {1:'图1 Caption'}, {...job,templateContract:{geometry:{...geometry,bodyBottomMm:265,columnWidthMm:85.5,columnGapMm:7}}}, []);
  assert.equal(result.pageId,next.page.id);
  assert.equal(result.pageTop,true);
  assert.equal(removed.length,3,'discard the two lower columns and tentative caption before the page-top retry');
  assert.equal(first.body.contents,'unchanged source story');
}
{
  const first = fixture(), next = fixture();
  first.body.textContainers.push(...first.body.textContainers);
  first.d.recompose = () => {
    if (first.marker.startParagraph === 'next-page') {
      first.marker.insertionPoints[0].parentTextFrames = [{parentPage: deferred(next.page)}];
      first.body.textContainers = next.body.textContainers;
    }
  };
  const spec = {numbers: [1], columns: 1, pageTop: false};
  const result = assembly.placePanel(first.d, first.body, spec, 0, {1: '图1 Caption'}, job, []);
  assert.equal(spec.pageTop, true);
  assert.equal(result.pageId, next.page.id);
  assert.equal(first.marker.contents, '\r');
}
const point = {};
const figure = assembly.placeFigure({pages: [{rectangles: {add: () => deferred(placed)}}], swatches: {itemByName: name => name}}, {insertionPoints: [point]}, {number: 3, height: 30, width: 80, path: 'figure.pdf'});
assert.equal(figure, placed);
assert.equal(figure.label, 'source-figure-3');
assert.equal(figure.anchoredObjectSettings.point, point);

for (const keep of [true, false]) {
  const f = fixture(), boundary = {contents: 'complete source paragraph\r'};
  const blanks = [{contents: '\r', startParagraph: 'next-page'}, {contents: ' \r', startParagraph: 'next-page'}];
  f.body.paragraphs = [boundary, ...blanks, f.following];
  const caption = {id: ++id, label: 'figure-band-caption-1', parentPage: f.page, geometricBounds: [60, 14.5, 115, 192.5]};
  f.d.allPageItems = [caption];
  f.body.textContainers = f.columns;
  context.File = () => ({encoding: '', open: () => true, read: () => JSON.stringify({blocks: [{role: 'body', text: 'complete source paragraph'}, {role: 'figure_caption', text: '图1 Caption'}]}), close() {}});
  const spec = {numbers: [1], columns: 1, pageTop: true, afterParagraphText: 'complete source paragraph', keepFollowingAfterPanel: keep};
  assembly.refreshPanels(f.d, f.body, {...job, logicalArticlePath: 'logical.json', panels: [spec]}, false);
  assert.equal(f.following.startParagraph, keep ? 'next-page' : 'anywhere');
  blanks.forEach(blank => assert.equal(blank.startParagraph, 'anywhere'));
  assert.equal(boundary.contents, 'complete source paragraph\r');
}

const guard = source.split(/\r?\n/).find(line => line.includes('fail("PANEL_PAGE_DRIFT"'));
assert.ok(guard, 'assembly final panel guard');
context.guardDocument = {allPageItems: [{id: 9, parentPage: {id: 4}}], recompose() {}};
context.guardResult = {panels: [{pageId: 4, frameIds: [9]}]};
vm.runInContext('(function(d,result){function item(doc,id){return doc.allPageItems.find(x=>x.id===id);}function fail(code,index){throw Error(code+" "+index);}' + guard + '})(guardDocument,guardResult);', context);
context.guardDocument.allPageItems[0].parentPage.id = 5;
assert.throws(() => vm.runInContext('(function(d,result){function item(doc,id){return doc.allPageItems.find(x=>x.id===id);}function fail(code,index){throw Error(code+" "+index);}' + guard + '})(guardDocument,guardResult);', context), /PANEL_PAGE_DRIFT 0/);

const footer = supplement => Array.from(assembly.footerEntries(supplement, {fund: 0}), item => ({...item}));
assert.deepEqual(footer({received: '收稿日期：2026-10-20', front: []}), [{role: 'received', text: '收稿日期：2026-10-20'}]);
assert.equal(footer({received: '日期', front: [{text: '  \r'}]}).length, 1);
assert.deepEqual(footer({received: '日期', front: [{text: '基金项目：编号123'}]}), [{role: 'received', text: '日期'}, {role: 'fund', text: '基金项目：编号123'}]);
console.log('PASS stable panel objects and page IDs, following paragraph boundaries, refresh blank markers, final page drift rejection, optional fund');
