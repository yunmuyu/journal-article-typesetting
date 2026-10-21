const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const context=vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_layout_measurement.jsxinc'),'utf8'),context);
const point={index:40,parentTextFrames:[{id:9}]};
const line={contents:'诊断文字',paragraphs:[{contents:'诊断文字',appliedParagraphStyle:{name:'正文'}}],insertionPoints:[point],get baseline(){throw Error('unavailable');}};
line.insertionPoints[-1]=point;
assert.throws(()=>context.JournalLayoutMeasurement.lineRecord(line),/LINE_METRIC_UNAVAILABLE.*40.*诊断文字/);
console.log('PASS unavailable line metrics identify the actual source text and offset');
