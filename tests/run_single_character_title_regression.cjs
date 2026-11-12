const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_frontmatter.jsxinc'),'utf8'),context);
const fit = context.JournalFrontmatter.fitSingleCharacterTitle;
function title(last, limit, widen=Infinity) {
    const paragraph = {tracking:0, contents:'首行标题'+last, textStyleRanges:{everyItem:()=>({getElements:()=>[{tracking:0}]})}};
    const attempts=[];
    const document = {recompose(){
        attempts.push(paragraph.tracking);
        paragraph.lines = paragraph.tracking<=limit ? [{contents:paragraph.contents}]
            : paragraph.tracking>=widen ? [{contents:'首行标'},{contents:'题'+last}]
            : [{contents:'首行标题'},{contents:last}];
    }};
    return {paragraph, document, attempts};
}
const one=title('现',-4);
assert.equal(fit(one.document,one.paragraph).to,-4);
assert.deepEqual(one.attempts,[0,-1,-2,-3,-4]);
const normal=title('两个',-3);
assert.equal(fit(normal.document,normal.paragraph),null);
assert.deepEqual(normal.attempts,[0]);
const tooLong=title('字',-21);
assert.equal(fit(tooLong.document,tooLong.paragraph),null);
assert.equal(tooLong.paragraph.tracking,0);
assert.equal(tooLong.paragraph.lines.length,2);
const widened=title('究',-21,3);
assert.equal(fit(widened.document,widened.paragraph).to,3);
assert.deepEqual(widened.attempts.slice(-3),[1,2,3]);
console.log('PASS title tests actual reflow, chooses the first fitting local value and restores blocked trials');
