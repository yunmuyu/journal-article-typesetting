const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const ctx=vm.createContext({});vm.runInContext(fs.readFileSync('2-导入_InDesign/journal_layout_rules.jsxinc','utf8'),ctx);
function make(count,styleLeading=25){
 const style=Object.freeze({leading:styleLeading,spaceBefore:0,spaceAfter:0});const lines=Array.from({length:count},()=>({value:25,characters:{everyItem(){const owner=this.owner;return Object.defineProperty({},'leading',{set(v){owner.value=v;}});}}}));for(const l of lines)l.characters.owner=l;
 const p={appliedParagraphStyle:style,lines,spaceBefore:0,spaceAfter:0};Object.defineProperty(p,'leading',{set(v){for(const l of lines)l.value=v;}});return {p,style,lines};
}
for(const count of [1,2,3]){const {p,style,lines}=make(count);ctx.JournalLayout.applyEnglishAffiliationSpacing(p);assert.equal(style.leading,25);assert.deepEqual(lines.map(x=>x.value),Array.from({length:count},(_,i)=>i===count-1?25:15));}
const bad=make(2,15);assert.throws(()=>ctx.JournalLayout.applyEnglishAffiliationSpacing(bad.p),/EN_AFFILIATION_STYLE_CONTRACT/);
console.log('PASS original 25pt paragraph style stays immutable; only wrapped internal lines receive 15pt local leading');

assert.ok(!/EN_AFFILIATION_LEADING/.test(fs.readFileSync('2-导入_InDesign/journal_layout_rules.jsxinc','utf8')),'contradictory legacy whole-paragraph 15pt gate must not reject a single-line 25pt affiliation');
