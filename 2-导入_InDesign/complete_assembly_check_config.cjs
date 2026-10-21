const fs = require('node:fs');
const read = path => JSON.parse(fs.readFileSync(path, 'utf8').replace(/^\uFEFF/, ''));
function derive(config, assembly, snapshot, formulas) {
  const out = structuredClone(config);
  out.documentPath = assembly.outputPath;
  out.bindings = assembly.bindings;
  if (formulas?.mode === 'native-idms') {
    out.formulaCacheContract = formulas.entries.map(entry => Object.fromEntries(
      ['number', 'cacheKey', 'sha256', 'sourceSha256', 'ruleVersion'].map(key => {
        if (entry[key] === undefined || entry[key] === '') throw Error('FORMULA_CACHE_CONTRACT_MISSING ' + key);
        return [key, entry[key]];
      })));
  }
  out.figurePanels = structuredClone(assembly.panels);
  out.localBottomPairs = [];
  out.widePanelFrameBreaks = [];
  const frames = snapshot.stories.find(s => s.role === 'body').frames;
  const pages = new Map();
  frames.forEach((f, i) => {
    if (!pages.has(f.page)) pages.set(f.page, []);
    pages.get(f.page).push({ ...f, index: i });
  });
  for (const group of pages.values()) {
    if (group.length === 2) continue;
    if (group.length !== 4) throw Error('UNSUPPORTED_PANEL_FRAME_STRUCTURE');
    const ordered = group.sort((a, b) => a.bounds[0] - b.bounds[0] || a.bounds[1] - b.bounds[1]);
    if (Math.abs(ordered[0].bounds[0] - ordered[1].bounds[0]) > .02 ||
        Math.abs(ordered[2].bounds[0] - ordered[3].bounds[0]) > .02) throw Error('PANEL_FRAME_ROWS');
    out.localBottomPairs.push({ frames: [ordered[0].index, ordered[1].index] });
    out.widePanelFrameBreaks.push([ordered[1].index, ordered[2].index]);
  }
  return out;
}
module.exports = { derive };
if (require.main === module) {
  const [jobPath, snapshotPath, outputPath] = process.argv.slice(2);
  const job = read(jobPath);
  const out = derive(read(job.auditConfigPath), read(job.resultPath), read(snapshotPath).candidate, job.formulas);
  fs.writeFileSync(outputPath, JSON.stringify(out, null, 2) + '\n');
  console.log(JSON.stringify({ outputPath, localBottomPairs: out.localBottomPairs, widePanelFrameBreaks: out.widePanelFrameBreaks }));
}
