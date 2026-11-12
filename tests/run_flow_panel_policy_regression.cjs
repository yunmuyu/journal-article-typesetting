const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');const c={};vm.createContext(c);vm.runInContext(fs.readFileSync('2-导入_InDesign/journal_article_assembly.jsxinc','utf8'),c);
const job={templateContract:{geometry:{columnWidthMm:85.5}},assets:[{kind:'figure',number:3,width:35},{kind:'figure',number:4,width:35}]},spec={numbers:[3,4],columns:2};
assert.ok(c.JournalArticleAssembly.flowPanelWidth(spec,job));job.assets[1].width=60;assert.equal(c.JournalArticleAssembly.flowPanelWidth(spec,job),null);assert.throws(()=>c.JournalArticleAssembly.flowPanelWidth({...spec,flowWithText:true},job),/REQUIRES_WIDE/);
vm.runInContext(fs.readFileSync('2-导入_InDesign/journal_frontmatter.jsxinc','utf8'),c);
assert.equal(c.JournalFrontmatter.affiliationBoundary('(1.School A;2.School B)').start,12);
assert.equal(c.JournalFrontmatter.affiliationBoundary('(School A; School B)'),null);
function tryAffiliations(text, naturalLines, separatedLines) {
    let contents = text;
    const replace = (start, length) => ({
        set contents(value) {
            contents = contents.slice(0, start) + value + contents.slice(start + length);
        },
    });
    const paragraph = {
        get contents() { return contents; },
        get lines() { return {length: contents.includes('\n') ? separatedLines : naturalLines}; },
        characters: {itemByRange: (start, end) => replace(start, end - start + 1)},
        insertionPoints: new Proxy({}, {get: (_, index) => replace(Number(index), 0)}),
    };
    c.JournalFrontmatter.separateAffiliations({recompose() {}}, paragraph);
    return contents;
}
assert.equal(tryAffiliations('(1.A; 2.B)', 2, 2), '(1.A;\n2.B)');
assert.equal(tryAffiliations('（1．甲；2．乙）', 2, 2), '（1．甲；\n2．乙）');
assert.equal(tryAffiliations('(1.A; 2.B; 3.C)', 2, 3), '(1.A; 2.B; 3.C)');
assert.equal(tryAffiliations('(1.A; 2.B)', 2, 3), '(1.A; 2.B)');
const breaksMatch = (contents, length) =>
    c.JournalFrontmatter.affiliationBreaksMatchLines({contents, lines: {length}});
assert.equal(breaksMatch('(1.A; 2.B)', 3), true);
assert.equal(breaksMatch('（1．甲；\n2．乙）', 2), true);
assert.equal(breaksMatch('(1.A;\n2.B; 3.C)', 3), false);
console.log('PASS no shrink flow selection and numbered affiliation separation');
