/* Approved geometry is article data; paragraph ordinals and page coordinates are not rules. */
const clean = text => String(text).replace(/[\s\uFFFC\u0016]/g, '');
const figureNumber = text => Number(String(text).match(/^图\s*(\d+)\s/)?.[1]);
const samePath = (a, b) => a.replaceAll('\\', '/').toLowerCase() === b.replaceAll('\\', '/').toLowerCase();

function fromApproved(snapshot, job, blocks) {
  const bodies = snapshot.stories.filter(s => s.role === 'body');
  if (bodies.length !== 1) throw Error('PROFILE_BODY_COUNT');
  const body = bodies[0];
  const profile = {schemaVersion: 1, figures: [], tables: [], placements: [], formulas: []};
  for (const asset of job.assets.filter(a => a.kind === 'figure')) {
    const matches = snapshot.objects.filter(o => o.label === `source-figure-${asset.number}`);
    if (matches.length !== 1 || matches[0].links.length !== 1 ||
        !samePath(matches[0].links[0].path, asset.path)) throw Error(`PROFILE_FIGURE_SOURCE ${asset.number}`);
    const b = matches[0].bounds;
    const width = b[3] - b[1], height = b[2] - b[0];
    if (!(width > 0 && height > 0) || Math.abs(width / height / (asset.width / asset.height) - 1) > .002)
      throw Error(`PROFILE_FIGURE_ASPECT ${asset.number}`);
    profile.figures.push({number: asset.number, path: asset.path, width, height});
  }
  for (const spec of job.tables) {
    const matches = body.tables.filter(t => t.label === `source-table-${spec.number}`);
    if (matches.length !== 1) throw Error(`PROFILE_TABLE_SOURCE ${spec.number}`);
    const table = matches[0], minimumHeightsMm = [];
    for (let row = 0; row < table.rows; row++) {
      const heights = table.cells.filter(c => c.row === row && c.rowSpan === 1).map(c => c.height);
      if (!heights.length || Math.max(...heights) - Math.min(...heights) > .02)
        throw Error(`PROFILE_TABLE_ROW ${spec.number}/${row}`);
      const height = heights[0];
      // A multiline row keeps natural growth; only approved single-line geometry is a minimum.
      minimumHeightsMm.push(height >= 4.8 - .001 && height <= 5.5 + .001 ? height : 5);
    }
    profile.tables.push({number: spec.number, widthsMm: table.widths, minimumHeightsMm});
  }
  for (const spec of job.figures.filter(f => f.mode === 'inline')) {
    const index = body.paragraphs.findIndex(p => figureNumber(p.text) === spec.number);
    if (index < 0) throw Error(`PROFILE_CAPTION ${spec.number}`);
    const next = body.paragraphs.slice(index + 1).find(p => clean(p.text));
    if (!next || !new RegExp(`图\\s*${spec.number}(?!\\d)`).test(next.text) || next.style === '图注/表名') continue;
    const source = blocks.map((b, i) => ({b, i})).filter(x => clean(x.b.text) === clean(next.text));
    const captionIndex = blocks.findIndex(b => b.role === 'figure_caption' && figureNumber(b.text) === spec.number);
    if (source.length !== 1 || captionIndex < 0) throw Error(`PROFILE_REFERENCE ${spec.number}`);
    if (source[0].i < captionIndex)
      profile.placements.push({number: spec.number, beforeParagraphText: next.text.replace(/\r$/, '')});
  }
  for (const p of body.paragraphs.filter(p => p.style === '公式')) {
    const number = Number(p.text.match(/[（(](\d+)[）)]/)?.[1]);
    const leadingPt = Math.max(...p.ranges.map(r => r.leading));
    if (!number || !Number.isFinite(leadingPt) || leadingPt < 15) throw Error('PROFILE_FORMULA_LEADING');
    profile.formulas.push({number, leadingPt});
  }
  return profile;
}

module.exports = {fromApproved};
