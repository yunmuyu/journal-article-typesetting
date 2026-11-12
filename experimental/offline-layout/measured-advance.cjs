const { createHash } = require('node:crypto');

function pairSignature(pair) {
  if (!pair || pair.columnStart || typeof pair.compositionKey !== 'string' ||
      !pair.compositionKey.trim() || !Number.isFinite(pair.widthMm) || pair.widthMm <= 0 ||
      !Array.isArray(pair.lines) || pair.lines.length !== 2) return null;
  if (pair.lines.some((line) => !line || !Number.isSafeInteger(line.start) ||
      !Number.isSafeInteger(line.end) || line.start < 0 || line.end <= line.start ||
      typeof line.text !== 'string')) return null;
  const [previous, current] = pair.lines;
  if (previous.end !== current.start || previous.hasTable || current.hasTable) return null;
  return createHash('sha256').update(JSON.stringify([pair.widthMm, pair.compositionKey,
    ...pair.lines.map((line) => [line.start, line.end, line.text, line.style, line.role,
      line.paragraphStart, line.paragraphEnd, line.leading, line.ascent, line.descent, line.anchors])])).digest('hex');
}

function reuseAdvance(measured, candidate) {
  const source = pairSignature(measured);
  if (!source || source !== pairSignature(candidate)) return null;
  const [previous, current] = measured.lines;
  if (!Number.isFinite(previous.baseline) || !Number.isFinite(current.baseline)) return null;
  const advance = current.baseline - previous.baseline;
  return Number.isFinite(advance) && advance > 0 ? advance : null;
}

module.exports = { pairSignature, reuseAdvance };
