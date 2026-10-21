const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(path.join(__dirname, '../2-导入_InDesign/Export-JournalPreviewPdf.ps1'), 'utf8');
const script = source.match(/\(function\(job\)\{var session=null[\s\S]*?\}\)\(PreviewJob\);/)[0];
function run(range, options = {}) {
  const original = {pageRange:'original', viewPDF:true, exportReaderSpreads:true};
  const prefs = {...original};
  const exports = [];
  let closed = 0;
  const document = {modified:false, pages:Array.from({length:210}, (_, i) => ({name:String(i - 5)})), exportFile(){
    exports.push(prefs.pageRange);
    if(options.failExport) throw Error('EXPORT_FAILED');
  }};
  const result = JSON.parse(vm.runInNewContext(script, {
    PreviewJob:{path:'fixture_QA.indd', output:'fixture.pdf', articlePageRange:range},
    app:{pdfExportPreferences:prefs}, PageRange:{ALL_PAGES:999}, ExportFormat:{PDF_TYPE:1}, SaveOptions:{NO:0},
    File:() => ({exists:true}), JournalRegressionSnapshot:{json:JSON.stringify},
    JournalDocumentSession:{acquire:() => ({document, openedHere:!options.preopened}), close(){closed++;}}
  }));
  assert.deepEqual(prefs, original, 'Export preferences must always be restored');
  assert.equal(closed, options.preopened ? 0 : 1, 'Only owned documents should close');
  return {result, exports};
}
let actual = run([204,209]);
assert.deepEqual(actual.exports, ['+205-+210'], 'Select absolute document pages, independent of printed section numbering');
assert.equal(actual.result.pages, 6, 'Expected PDF count is the selected article, not the whole issue');
assert.equal(actual.result.documentPages, 210);
actual = run(null);
assert.deepEqual(actual.exports, [999]);
assert.equal(actual.result.pages, 210);
for (const range of [[204,210], [205,204], [-1,3], [2], [1.5,3]]) {
  actual = run(range);
  assert.equal(actual.result.status, 'failed');
  assert.match(actual.result.error, /PREVIEW_ARTICLE_PAGE_RANGE/);
  assert.equal(actual.exports.length, 0);
}
actual = run([204,209], {failExport:true, preopened:true});
assert.equal(actual.result.status, 'failed');
assert.match(actual.result.error, /EXPORT_FAILED/);
console.log('PASS scoped PDF export selects absolute pages, counts subset, rejects invalid ranges and restores ownership/preferences');
