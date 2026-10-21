const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const context = { VerticalJustification: { TOP_ALIGN: "top", CENTER_ALIGN: "center" } };
vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(__dirname, "../2-导入_InDesign/journal_layout_rules.jsxinc"), "utf8"), context);
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
        stories: [body], pages: collection([{ id: 2 }, { id: 3 }]),
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

{
    // Given: all intervals except the first are at the maximum.
    const f = fixture(253.3, [15, 16, 16]);
    // When: align to the existing target without changing its tolerance.
    layout.alignBottom(f.document);
    // Then: the first interval closes the gap; no terminal-line write leaks.
    assert.ok(Math.abs(layout.last(f.frame) - (265 - layout.rules.bottomInset)) < 0.001,
        "the first line's adjustable interval must reach the frame bottom");
    assert.ok(f.writes.includes(0), "first interval was never adjusted");
    assert.ok(!f.writes.includes(2), "terminal leading must not alter following-frame flow");
}

{
    // Given: a local frame needs a small reduction and only its first interval can shrink.
    const f = fixture(100, [15, 14.8, 14.8]);
    const target = layout.visibleBottom(f.frame) - 0.03;
    const fixed = fixture(target - 0.3, [15]).frame;
    fixed.id = 12;
    f.body.textContainers = [fixed, f.frame];
    // These are local figure-band frames, not full-height page columns.
    fixed.geometricBounds[2] = 120;
    f.frame.geometricBounds[2] = 120;
    // When: align the two visible bottoms.
    layout.alignLocalBlocks(f.document, { localBottomPairs: [{ frames: [0, 1] }] });
    // Then: the adjustable first interval reaches the other frame.
    assert.ok(Math.abs(layout.visibleBottom(f.frame) - target) < 0.001,
        "local bottom alignment must include the first interval");
    assert.ok(!f.writes.includes(2), "local alignment wrote the terminal line");
}

{
    // Given: a collection exposes a next line owned by another frame.
    const f = fixture(253.3, [15, 15, 15]);
    f.frame.lines[2].insertionPoints[0].parentTextFrames = [{ id: 99 }];
    // When: solve the current frame.
    layout.alignBottom(f.document);
    // Then: no interval crossing a frame boundary is adjusted.
    assert.ok(!f.writes.includes(1), "interval crossing to another frame must be excluded");
    assert.ok(!f.writes.includes(2), "foreign terminal line must be excluded");
}

{
    // Given: the desired baseline exceeds the frame's composition capacity.
    const f = fixture(253.3, [15, 15, 15], 264.2);
    const initialBottom = layout.last(f.frame);
    const initialEndpoint = f.frame.lines[-1].insertionPoints[-1].index;
    // When: an initial leading increase would move the last line to the next frame.
    layout.alignBottom(f.document);
    // Then: backtrack to a useful bounded step without losing the original endpoint.
    assert.equal(f.frame.lines.length, 3, "bottom alignment displaced a line into the next frame");
    assert.equal(f.frame.lines[-1].insertionPoints[-1].index, initialEndpoint);
    assert.ok(layout.last(f.frame) > initialBottom, "backtracking made no valid progress");
    assert.ok(layout.last(f.frame) <= 264.2);
}

{
    const f = fixture(253.3, [16, 16, 16, 15], 270);
    assert.equal(f.frame.lines.length, 3);
    const endpoint = f.frame.lines[-1].insertionPoints[-1].index;
    layout.alignBottom(f.document);
    assert.equal(f.frame.lines.length, 3, "a leading reduction pulled in the following frame's line");
    assert.equal(f.frame.lines[-1].insertionPoints[-1].index, endpoint);
}

{
    const f = fixture(253.3, [15, 15, 15]);
    const recompose = f.document.recompose;
    let failed = false;
    f.document.recompose = function () {
        if (f.writes.length && !failed) {
            failed = true;
            throw Error("injected composition failure");
        }
        recompose();
    };
    assert.throws(() => layout.alignBottom(f.document), /injected composition failure/);
    assert.deepEqual(f.allLines.map(line => line.characters[0].leading), [15, 15, 15],
        "a failed trial must restore effective leading values");
}

{
    const f = fixture(253, [16, 16, 16]);
    const row = { minimumHeight: 4.8, get height() { return this.minimumHeight; }, cells: collection([]) };
    f.frame.tables = collection([{ rows: collection([row]) }]);
    const recompose = f.document.recompose;
    f.document.recompose = function () {
        recompose();
        for (const line of f.allLines) {
            line.baseline += row.minimumHeight - 4.8;
            for (const point of line.insertionPoints) {
                point.parentTextFrames = [line.baseline <= 264.31 ? f.frame : { id: 99 }];
            }
        }
        f.frame.lines = collection(f.allLines.filter(line => line.baseline <= 264.31));
    };
    layout.alignBottom(f.document);
    assert.equal(f.frame.lines.length, 3, "table-height fallback displaced the terminal line");
    assert.ok(row.minimumHeight > 4.8, "table-height backtracking made no valid progress");
    assert.ok(layout.last(f.frame) <= 264.31);
}

console.log("PASS leading intervals, bidirectional endpoints, exception rollback and table fallback");
