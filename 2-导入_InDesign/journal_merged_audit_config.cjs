const fs = require('node:fs');
function convert(source, placement, auditPath) {
  const {start, end, pageShiftsMm, bindings, target} = placement;
  if (!Number.isInteger(start) || !Number.isInteger(end) || start < 0 || end < start || pageShiftsMm.length !== end - start + 1 || pageShiftsMm.some(x => ![-3, 0, 3].includes(x))) throw Error('MERGED_PLACEMENT_INVALID');
  const result = JSON.parse(JSON.stringify(source));
  const sourceBindings = result.bindings || [];
  if (sourceBindings.length !== bindings.length || sourceBindings.some((b, i) => b.role !== bindings[i].role)) throw Error('MERGED_BINDING_ORDER_CHANGED');
  const storyIds = new Map(sourceBindings.map((b, i) => [b.id, bindings[i].id]));
  result.documentPath = target; result.auditPath = auditPath; result.bindings = bindings;
  result.articlePageRange = [start, end]; result.startOnLeft = false;
  for (const key of ['figurePanels', 'widePanelBoundaries']) for (const entry of result[key] || []) {
    if (!Number.isInteger(entry.pageIndex) || entry.pageIndex < 0 || entry.pageIndex >= pageShiftsMm.length) throw Error('SOURCE_DOCUMENT_PAGE_INVALID ' + key);
    entry.pageIndex += start;
  }
  const shift = pageShiftsMm[0];
  for (const anchor of result.fixedFrames || []) if (typeof anchor.left === 'number') anchor.left += shift;
  for (const anchor of result.templateAnchors || []) {anchor.bounds[1] += shift; anchor.bounds[3] += shift;}
  for (const entry of result.leadingExceptions || []) {
    if (!storyIds.has(entry.storyId)) throw Error('LEADING_EXCEPTION_STORY_NOT_BOUND');
    entry.storyId = storyIds.get(entry.storyId);
  }
  result.mergePlacementExplanation = {reason: 'Continuous issue pagination; translate by the actual left/right page margins without adding blank pages. Document page indices are rebased; master page and body frame indices stay local.', sourceDefaultLeft: source.startOnLeft !== false, pageShiftsMm};
  return result;
}
module.exports = {convert};
if (require.main === module) {
  const [sourcePath, placementPath, outputPath, auditPath] = process.argv.slice(2);
  const read = p => JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, ''));
  fs.writeFileSync(outputPath, JSON.stringify(convert(read(sourcePath), read(placementPath), auditPath), null, 2));
}
