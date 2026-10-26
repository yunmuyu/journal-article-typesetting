const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');const c={};vm.createContext(c);vm.runInContext(fs.readFileSync('2-导入_InDesign/journal_article_assembly.jsxinc','utf8'),c);
const job={templateContract:{geometry:{columnWidthMm:85.5}},assets:[{kind:'figure',number:3,width:35},{kind:'figure',number:4,width:35}]},spec={numbers:[3,4],columns:2};
assert.ok(c.JournalArticleAssembly.flowPanelWidth(spec,job));job.assets[1].width=60;assert.equal(c.JournalArticleAssembly.flowPanelWidth(spec,job),null);assert.throws(()=>c.JournalArticleAssembly.flowPanelWidth({...spec,flowWithText:true},job),/REQUIRES_WIDE/);
vm.runInContext(fs.readFileSync('2-导入_InDesign/journal_frontmatter.jsxinc','utf8'),c);
assert.equal(c.JournalFrontmatter.affiliationBoundary('(1.School A;2.School B)').start,12);
assert.equal(c.JournalFrontmatter.affiliationBoundary('(School A; School B)'),null);
console.log('PASS no shrink flow selection and numbered affiliation separation');
