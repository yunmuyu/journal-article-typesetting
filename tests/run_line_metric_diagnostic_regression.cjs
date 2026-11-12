const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const context=vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_layout_measurement.jsxinc'),'utf8'),context);
const point={index:40,parentTextFrames:[{id:9}]};
const line={contents:'诊断文字',paragraphs:[{contents:'诊断文字',appliedParagraphStyle:{name:'正文'}}],insertionPoints:[point],get baseline(){throw Error('unavailable');}};
line.insertionPoints[-1]=point;
assert.throws(()=>context.JournalLayoutMeasurement.lineRecord(line),/LINE_METRIC_UNAVAILABLE.*40.*诊断文字/);
console.log('PASS unavailable line metrics identify the actual source text and offset');

function composedLine(start, baseline, {leading=15, mixed=false, text='正文'}={}) {
    const insertionPoints=[{index:start}];
    insertionPoints[-1]={index:start+3};
    const characters=[{index:start}];
    characters[-1]={index:start+2,leading};
    const styles=mixed?[{leading},{leading:16}]:[{leading}];
    return {
        contents:text, baseline, insertionPoints, characters,
        paragraphs:[{contents:text,appliedParagraphStyle:{name:'journal-123::正文'},tables:[]}],
        textStyleRanges:{everyItem:()=>({getElements:()=>styles})},
    };
}
const frame={id:9,parentPage:{name:'27',documentOffset:25},geometricBounds:[26,15,265,198],
    textFramePreferences:{textColumnCount:2}};
context.JournalLayout={
    rules:{bottomInset:0.655},
    nativeFlowBands(f){
        assert.equal(f,frame);
        return {signature:'known-breaks',bands:[
            {cut:true,left:[composedLine(1,60)],right:[]},
            {cut:false,left:[composedLine(10,220),composedLine(13,225),composedLine(16,230,{mixed:true})],
                right:[composedLine(40,220),composedLine(43,225,{text:'\uFFFC'})]},
        ]};
    },
};
const story={id:5,overflows:false,textContainers:[frame,{...frame,parentPage:{name:'28',documentOffset:26}}]};
const measured=context.JournalLayoutMeasurement.captureNativeBands(story,[25]);
assert.equal(measured.frames.length,1);
assert.equal(measured.frames[0].signature,'known-breaks');
assert.equal(measured.frames[0].bands[0].right,null);
const lower=measured.frames[0].bands[1];
assert.equal(lower.left.end,19);
assert.equal(lower.left.bottomMm,230);
assert.equal(lower.left.leadingRanges.length,1);
assert.equal(lower.left.leadingRanges[0].start,13);
assert.equal(lower.left.estimatedLocalMaxPt,1);
assert.equal(lower.right.leadingRanges.length,0);
assert.throws(()=>context.JournalLayoutMeasurement.captureNativeBands(story,[]),/NATIVE_BAND_PAGES_REQUIRED/);
console.log('PASS native bands preserve scoped endpoints and exclude first lines, mixed leading and anchors from capacity');
