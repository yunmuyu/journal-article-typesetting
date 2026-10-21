// Snapshot comparison is independent of the layout solver and never changes a document.
const fs = require('node:fs');
const CONTRACT_VERSION = 'format-contract-1';
const strictCharacter = ['font', 'fontStyle', 'pointSize', 'position', 'baselineShift', 'horizontalScale', 'verticalScale'];
const strictParagraph = ['justification', 'firstLineIndent', 'leftIndent', 'rightIndent', 'lastLineIndent'];
const ignore = /[\s\uFFFC\u0016]/;
const same = (a, b) => typeof a === 'number' && typeof b === 'number' ? Math.abs(a - b) < 0.001 : JSON.stringify(a) === JSON.stringify(b);
const key = text => String(text).replace(/[\s\uFFFC\u0016]/g, '');
const family = name => String(name).split('\t')[0];
function chars(p) {
  const result = [];
  for (let i = 0; i < p.text.length; i++) {
    if (ignore.test(p.text[i])) continue;
    const run = p.ranges.find(r => i >= r.start && i < r.start + r.text.length);
    result.push({ char: p.text[i], offset: i, run });
  }
  return result;
}
function tabSignature(text) {
  let visible = 0;
  const result = [];
  for (const character of text) {
    if (character === '\t') result.push(visible);
    else if (!ignore.test(character)) visible++;
  }
  return result;
}
function paragraphEntries(snapshot) {
  const result = [];
  for (const story of snapshot.stories) { let startIndex = 0; for (const p of story.paragraphs) {
    const paragraphStart = p.startIndex ?? startIndex; startIndex += p.text.length;
    if (!key(p.text)) continue;
    // Captions may move from a body story to a separate wide-panel story.
    const group = /^图\s*\d/.test(p.text) && /图注|表名/.test(p.style) ? 'figureCaption' : story.role;
    result.push({ ...p, startIndex: paragraphStart, group, location: `${story.role}/p/${p.ordinal}` });
  }
  } return result;
}
function fontDescription(snapshot, run) {
  const composite = (snapshot.compositeFonts || []).find(f => f.name === family(run.font));
  return composite ? { composite: composite.entries } : { font: family(run.font) };
}
function inheritedCompositeFaceEquivalent(baseline, candidate, a, b, evidence = []) {
  if (a.font !== b.font || a.characterStyle !== b.characterStyle || !['', 'Regular'].includes(a.fontStyle) || !['', 'Regular'].includes(b.fontStyle)) return false;
  const font = family(a.font), composite = (baseline.compositeFonts || []).find(f => f.name === font);
  if (!composite || !same(fontDescription(baseline, a), fontDescription(candidate, b))) return false;
  const xmlFont = font.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  return evidence.some(e => e.name === a.characterStyle && e.sourceDefinition && e.sourceDefinition === e.targetDefinition &&
    !/<CharacterStyle[^>]* FontStyle=/.test(e.sourceDefinition) && e.sourceDefinition.includes('<AppliedFont type="string">' + xmlFont + '</AppliedFont>'));
}
function rangeLeadingLimits(limits, paragraph, run, config = {}) {
  const result = limits.slice(), binding = (config.bindings || []).find(b => b.role === paragraph.group);
  if (!binding) return result;
  const start = paragraph.startIndex + run.start, end = start + run.text.length - 1;
  for (const e of config.leadingExceptions || []) if (e.storyId === binding.id && start >= e.startIndex && end <= e.endIndex && e.reason) {
    if (e.userApproved === true && e.minPt >= 14.7 && e.minPt < result[0]) result[0] = e.minPt;
    if (e.maxPt > result[1] && e.maxPt <= 16.05) result[1] = e.maxPt;
  }
  return result;
}
function compare(baseline, candidate, quality, definitionEvidence = [], qualityConfig = {}) {
  const failures = [], variations = [], explainedDifferences = [], measured = { paragraphs: 0, characters: 0, cells: 0, anchors: 0 };
  const fail = (code, location, field, expected, actual) => failures.push({ code, location, field, expected, actual });
  for (const [name, snapshot] of [['baseline', baseline], ['candidate', candidate]]) {
    if (snapshot.schemaVersion !== 1) fail('SNAPSHOT_VERSION', name, 'schemaVersion', 1, snapshot.schemaVersion);
    if (snapshot.unavailable.length) fail('SNAPSHOT_INCOMPLETE', name, 'unavailable', [], snapshot.unavailable);
  }
  function compareParagraph(a, b, location, table = false) {
    measured.paragraphs++;
    if (key(a.text) !== key(b.text)) {
      fail('CONTENT_MISMATCH', location, 'text', a.text, b.text);
      return;
    }
    if (!same(tabSignature(a.text), tabSignature(b.text))) fail('TAB_CHARACTERS', location, 'text', a.text, b.text);
    if (!same(a.tabs, b.tabs)) fail('TAB_STOPS', location, 'tabs', a.tabs, b.tabs);
    for (const field of strictParagraph) if (!same(a.properties[field], b.properties[field])) {
      fail('PARAGRAPH_FORMAT', location, field, a.properties[field], b.properties[field]);
    }
    const ac = chars(a), bc = chars(b);
    const differences = {};
    for (let i = 0; i < ac.length; i++) {
      const ar = ac[i].run, br = bc[i].run;
      measured.characters++;
      if (!ar || !br) {
        differences.unmeasured ||= [];
        differences.unmeasured.push(bc[i].offset);
        continue;
      }
      for (const field of strictCharacter) {
        let equal = same(ar[field], br[field]);
        if (field === 'font' && !equal) equal = same(fontDescription(baseline, ar), fontDescription(candidate, br));
        if (!equal && field === 'fontStyle' && inheritedCompositeFaceEquivalent(baseline, candidate, ar, br, definitionEvidence)) {
          equal = true; explainedDifferences.push({ location, offset: bc[i].offset, field, expected: ar[field], actual: br[field], reason: 'Identical exported character definition and composite glyph mappings; inherited DOM face representation', characterStyle: ar.characterStyle });
        }
        if (!equal) {
          differences[field] ||= [];
          differences[field].push({ offset: bc[i].offset, text: bc[i].char, expected: ar[field], actual: br[field] });
        }
      }
    }
    for (const [field, details] of Object.entries(differences)) {
      if (field === 'unmeasured') fail('CHARACTER_UNMEASURED', location, 'ranges', 'every visible character measured', details);
      else failures.push({ code: 'CHARACTER_FORMAT', location, field, details });
    }
    const body = /^(正文|正文_wrd_1|期刊正文_)/.test(b.style);
    const ref = b.style === '参考文献 内容';
    const bio = /^作者简介/.test(b.text);
    for (const r of b.ranges) {
      if (!key(r.text)) continue;
      let limits = table ? [12, 12] : body ? [14.8, 16] : ref ? [12.6, 13.4] : bio && r.pointSize === 9 ? [12.6, 13.4] : null;
      if (limits && body && !table) limits = rangeLeadingLimits(limits, b, r, qualityConfig);
      if (limits && !(typeof r.leading === 'number' && r.leading >= limits[0] - 0.001 && r.leading <= limits[1] + 0.001)) {
        fail('LEADING_RANGE', location, 'leading', limits, r.leading);
      }
      if (body && Math.abs(r.tracking) > 20.001) fail('TRACKING_RANGE', location, 'tracking', [-20, 20], r.tracking);
    }
    const changed = [];
    if (a.text !== b.text) changed.push('spacing-or-line-breaks');
    if (a.style !== b.style) changed.push('style-name');
    for (const field of Object.keys(a.properties)) if (!strictParagraph.includes(field) && !same(a.properties[field], b.properties[field])) changed.push(field);
    for (const field of ['leading', 'tracking', 'noBreak', 'kerningMethod']) {
      if (ac.some((x, i) => x.run && bc[i].run && !same(x.run[field], bc[i].run[field]))) changed.push(field);
    }
    if (changed.length) variations.push({ location, fields: changed, requiresQualityGate: true });
  }
  const actual = paragraphEntries(candidate), used = new Set();
  for (const p of paragraphEntries(baseline)) {
    const index = actual.findIndex((v, i) => !used.has(i) && p.group === v.group && key(v.text) === key(p.text));
    if (index < 0) { fail('CONTENT_MISSING', p.location, 'text', p.text, null); continue; }
    used.add(index);
    compareParagraph(p, actual[index], actual[index].location);
  }
  actual.forEach((p, i) => { if (!used.has(i)) fail('CONTENT_ADDED', p.location, 'text', null, p.text); });
  const tables = snapshot => snapshot.stories.flatMap(s => s.tables.map((table, i) => ({ ...table, location: `${s.role}/table/${i}` })));
  const bt = tables(baseline), ct = tables(candidate);
  if (bt.length !== ct.length) fail('TABLE_COUNT', 'tables', 'count', bt.length, ct.length);
  for (let i = 0; i < Math.min(bt.length, ct.length); i++) {
    const a = bt[i], b = ct[i];
    for (const field of ['rows', 'columns', 'headerRowCount', 'footerRowCount']) if (!same(a[field], b[field])) fail('TABLE_STRUCTURE', b.location, field, a[field], b[field]);
    const cells = t => t.cells.map(c => [c.row, c.column, c.rowSpan, c.columnSpan]);
    if (!same(cells(a), cells(b))) fail('TABLE_MERGE', b.location, 'cells', cells(a), cells(b));
    for (const cell of a.cells) {
      const other = b.cells.find(c => c.row === cell.row && c.column === cell.column);
      if (!other) continue;
      measured.cells++;
      const location = `${b.location}/cell/${cell.row},${cell.column}`;
      if (key(cell.text) !== key(other.text)) fail('TABLE_CONTENT', location, 'text', cell.text, other.text);
      if (other.overflows) fail('CELL_OVERSET', location, 'overflows', false, true);
      if (cell.paragraphs.length !== other.paragraphs.length) fail('TABLE_PARAGRAPHS', location, 'count', cell.paragraphs.length, other.paragraphs.length);
      for (let p = 0; p < Math.min(cell.paragraphs.length, other.paragraphs.length); p++) compareParagraph(cell.paragraphs[p], other.paragraphs[p], location + '/p/' + p, true);
    }
  }
  for (const role of ['front', 'footer', 'doi']) {
    const a = baseline.stories.find(s => s.role === role), b = candidate.stories.find(s => s.role === role);
    if (!a || !b || a.frames.length !== 1 || b.frames.length !== 1) { fail('ANCHOR_MISSING', role, 'frames', 1, b?.frames.length); continue; }
    const af = a.frames[0], bf = b.frames[0];
    const fields = role === 'front' ? [0, 1, 3] : role === 'footer' ? [1, 2, 3] : [0, 1, 2, 3];
    for (const coordinate of fields) {
      measured.anchors++;
      if (!same(af.bounds[coordinate], bf.bounds[coordinate])) fail('FIXED_ANCHOR', role, `bounds[${coordinate}]`, af.bounds[coordinate], bf.bounds[coordinate]);
    }
    if (!same(af.inset, bf.inset)) fail('FIXED_ANCHOR', role, 'inset', af.inset, bf.inset);
  }
  return {
    contractVersion: CONTRACT_VERSION, measured, explainedDifferences, mustMatchPassed: failures.length === 0, failures,
    compliantVariationCandidates: variations,
    quality: quality || { passed: false, reason: 'Complete current-document quality gate is required separately' },
    passed: failures.length === 0 && quality?.passed === true
  };
}
module.exports = { compare, rangeLeadingLimits, inheritedCompositeFaceEquivalent, CONTRACT_VERSION };
if (require.main === module) {
  const [snapshotPath, outputPath] = process.argv.slice(2);
  if (!snapshotPath || !outputPath) throw Error('Usage: node journal_regression_contract.cjs snapshot.json report.json');
  const snapshot = JSON.parse(fs.readFileSync(snapshotPath, 'utf8').replace(/^\uFEFF/, ''));
  const result = compare(snapshot.baseline, snapshot.candidate);
  fs.writeFileSync(outputPath, JSON.stringify(result, null, 2) + '\n');
  console.log(JSON.stringify({ outputPath, measured: result.measured, failures: result.failures.length, variations: result.compliantVariationCandidates.length, mustMatchPassed: result.mustMatchPassed }));
  process.exitCode = result.mustMatchPassed ? 0 : 1;
}
