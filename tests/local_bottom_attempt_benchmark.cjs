const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const context = { VerticalJustification: { TOP_ALIGN: "top", CENTER_ALIGN: "center" } };
vm.createContext(context);
let source=fs.readFileSync(path.join(__dirname, "../2-导入_InDesign/journal_layout_rules.jsxinc"), "utf8");if(process.argv.includes("--baseline"))source=source.replace("choice<(fixed?1:2)","choice<2");vm.runInContext(source, context);
const layout = context.JournalLayout;
const mmPerPt = 25.4 / 72;

function collection(values) {
    values[-1] = values[values.length - 1];
    values.everyItem = () => ({ getElements: () => values });
    return values;
}

// The observed InDesign composer advances from line i by line i's leading.
// A terminal line's leading affects subsequent flow, not this frame's bottom.
function fixture(firstBaseline, leadings, maximumBaseline = Infinity) {
    const writes = [];
    const body = { id: 1, extractLabel: () => "body", overflows: false, paragraphs: [] };
    const empty = { id: 10, lines: [], geometricBounds: [26, 0, 100, 85.5], tables: collection([]) };
    const frame = {
        id: 11, parentPage: { documentOffset: 0 },
        geometricBounds: [26, 92.5, 265, 178],
        textFramePreferences: {}, tables: collection([])
    };
    const allLines = leadings.map((leading, index) => {
        const character = { index, leading };
        const paragraph = { contents: "正文", appliedParagraphStyle: { name: "正文" }, tables: [] };
        const insertion = { index, parentTextFrames: [frame] };
        return {
            baseline: 0, contents: "正文", paragraphs: [paragraph],
            characters: collection([character]),
            insertionPoints: collection([insertion, { index: index + 1, parentTextFrames: [frame] }]),
            createOutlines() {
                return [{ geometricBounds: [this.baseline - 2, 0, this.baseline + 0.3, 10],
                    isValid: true, remove() { this.isValid = false; } }];
            }
        };
    });
    frame.lines = collection(allLines.slice());
    body.textContainers = [empty, frame];
    body.characters = { itemByRange(start, end) {
        assert.equal(start, end);
        return {
            textStyleRanges: collection([{ leading: allLines[start].characters[0].leading,
                characters: collection([allLines[start].characters[0]]) }]),
            set leading(value) {
            writes.push(start);
            allLines[start].characters[0].leading = value;
        } };
    } };
    const document = {
        stories: [body], pages: collection([{id:2}, {id:3}]),
        recompose() {
            let baseline = firstBaseline;
            for (const line of allLines) {
                line.baseline = baseline;
                baseline += line.characters[0].leading * mmPerPt;
                if (Number.isFinite(maximumBaseline)) {
                    for (const point of line.insertionPoints) {
                        point.parentTextFrames = [line.baseline <= maximumBaseline ? frame : { id: 99 }];
                    }
                }
            }
            if (Number.isFinite(maximumBaseline)) {
                frame.lines = collection(allLines.filter(line => line.baseline <= maximumBaseline));
            }
        }
    };
    document.recompose();
    return { document, body, frame, writes, allLines };
}

const f=fixture(253.3,[15,15,15],264.2);let recompositions=0;const compose=f.document.recompose;f.document.recompose=function(){recompositions++;compose.call(this);};layout.alignLocalBlocks(f.document,{});console.log(JSON.stringify({recompositions,bottom:layout.last(f.frame),lines:f.frame.lines.length,end:f.frame.lines[-1].insertionPoints[-1].index}));
