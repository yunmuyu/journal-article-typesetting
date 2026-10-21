const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const project = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(project, '2-导入_InDesign', 'journal_prepreview_gate.jsxinc'), 'utf8');
vm.runInThisContext(source, {filename: 'journal_prepreview_gate.jsxinc'});

function collection(items) {
    items.everyItem = () => ({getElements: () => items.slice()});
    return items;
}
function makeLine(spec) {
    return {
        contents: spec.contents,
        baseline: spec.baseline,
        ascent: 3,
        descent: 1,
        horizontalOffset: spec.left,
        endHorizontalOffset: spec.right,
        insertionPoints: [{parentTextFrames: [spec.frame]}]
    };
}
function makeParagraph(spec) {
    const paragraph = {
        index: spec.index,
        role: spec.role,
        contents: spec.contents,
        tables: spec.hasTable ? [{}] : [],
        appliedParagraphStyle: {name: spec.role === 'body' ? '正文' : '表格占位'},
        insertionPoints: [{parentTextFrames: [spec.frame]}]
    };
    paragraph.textStyleRanges = collection([{contents: spec.hasTable ? '\uFFFC' : spec.contents, pointSize: spec.metrics.size, leading: spec.metrics.leading}]);
    paragraph.lines = collection([]);
    return paragraph;
}function makeFrame(page, bounds) {
    return {id: bounds.join('-'), parentPage: page, geometricBounds: bounds, lines: collection([]), tables: collection([])};
}

const pages = [
    {id: 1, documentOffset: 0, name: '1', isValid: true},
    {id: 2, documentOffset: 1, name: '2', isValid: true},
    {id: 3, documentOffset: 2, name: '3', isValid: true}
];
const firstFrame = makeFrame(pages[0], [0, 0, 100, 80]);
const secondFrame = makeFrame(pages[1], [0, 0, 100, 80]);
const trailingFrame = makeFrame(pages[2], [0, 0, 100, 80]);
const tableParagraph = makeParagraph({frame:firstFrame, index:0, role:'body', metrics:{size:10.5, leading:0.1}, contents:'\uFFFC', hasTable:true});
const pollutedBody = makeParagraph({frame:firstFrame, index:1, role:'body', metrics:{size:9, leading:0.1}, contents:'表后正文', hasTable:false});
const laterBody = makeParagraph({frame:secondFrame, index:2, role:'body', metrics:{size:10.5, leading:15}, contents:'后页正文', hasTable:false});
const tableLine = makeLine({page:pages[0], frame:firstFrame, contents:'表格内容', baseline:20, left:5, right:40});
const bodyLine = makeLine({page:pages[0], frame:firstFrame, contents:'表后正文', baseline:20, left:5, right:40});
const laterLine = makeLine({page:pages[1], frame:secondFrame, contents:'后页正文', baseline:95, left:5, right:40});
pollutedBody.lines.push(bodyLine);
laterBody.lines.push(laterLine);
firstFrame.lines.push(bodyLine);
secondFrame.lines.push(laterLine);
const cellRanges = collection([{contents: '表格内容', pointSize: 9, leading: 12}]);
const cell = {texts: [{textStyleRanges: cellRanges, lines: collection([tableLine])}]};
const row = {height: 10, cells: collection([cell])};
const table = {cells: collection([cell]), rows: collection([row])};
tableParagraph.tables = collection([table]);
firstFrame.tables.push(table);
const paragraphs = collection([tableParagraph, pollutedBody, laterBody]);
const story = {id: 7, paragraphs, extractLabel: () => 'body'};
const document = {pages, allPageItems: collection([])};
const context = {
    stories: collection([story]),
    body: {textContainers: collection([firstFrame, secondFrame, trailingFrame])},
    tables: collection([table]),
    classify: paragraph => paragraph.role,
    visibleBottom: frame => frame.lines.length ? frame.lines[frame.lines.length - 1].baseline + 1 : -Infinity
};

const errors = JournalPrepreviewGate.audit(document, {}, context);
const codes = errors.map(error => error.code);
for (const expected of ['TEXT_METRIC_INVALID', 'BODY_METRIC', 'TABLE_STYLE_POLLUTION', 'GEOMETRY_OVERLAP', 'TRAILING_BLANK_PAGE', 'LARGE_EMPTY_REGION']) {
    if (!codes.includes(expected)) throw new Error(`missing ${expected}: ${JSON.stringify(errors)}`);
}
if (codes.includes('TABLE_RESERVATION')) throw new Error(`inline table host marker was treated as text: ${JSON.stringify(errors)}`);
if (!errors.some(error => /page 1/.test(error.detail))) throw new Error('paragraph/page location is absent');

const isolatedPages = [
    {id: undefined, documentOffset: 0, name: '10', isValid: true},
    {id: undefined, documentOffset: 1, name: '11', isValid: true}
];
const isolatedFrames = [makeFrame(isolatedPages[0], [0, 0, 100, 80]), makeFrame(isolatedPages[1], [0, 0, 100, 80])];
const isolatedParagraphs = collection(isolatedFrames.map((frame, index) => {
    const paragraph = makeParagraph({frame, index, role:'body', metrics:{size:10.5, leading:15}, contents:`第${index + 1}页正文`, hasTable:false});
    const line = makeLine({frame, contents:paragraph.contents, baseline:20, left:5, right:40});
    paragraph.lines.push(line);
    frame.lines.push(line);
    return paragraph;
}));
const isolatedStory = {id: 8, paragraphs: isolatedParagraphs, extractLabel: () => 'body'};
const isolatedContext = {
    stories: collection([isolatedStory]),
    body: {textContainers: collection(isolatedFrames)},
    tables: collection([]),
    classify: paragraph => paragraph.role,
    visibleBottom: frame => frame.lines[frame.lines.length - 1].baseline + 1
};
const isolatedErrors = JournalPrepreviewGate.audit({pages: isolatedPages, allPageItems: collection([])}, {maxUnexplainedBlankMm:100}, isolatedContext);
if (isolatedErrors.some(error => error.code === 'GEOMETRY_OVERLAP')) throw new Error(`cross-page overlap false positive: ${JSON.stringify(isolatedErrors)}`);
console.log('PASS pre-preview gate reports numeric, overlap, blank-page and empty-region failures with location');
