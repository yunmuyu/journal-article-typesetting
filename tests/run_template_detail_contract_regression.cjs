const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const context=vm.createContext({});vm.runInContext(fs.readFileSync('2-导入_InDesign/journal_layout_rules.jsxinc','utf8'),context);
assert.equal(typeof context.JournalLayout.receivedSeparatorY,'function');
assert.ok(Math.abs(context.JournalLayout.receivedSeparatorY(255.424348962778,{receivedSeparatorBaselineGapMm:4.8965711806})-250.527777782178)<1e-10);
assert.throws(()=>context.JournalLayout.receivedSeparatorY(255,{}),/RECEIVED_SEPARATOR_CONTRACT/);
assert.equal(typeof context.JournalLayout.applyBiographyLabelStyle,'function');
const style={name:'12磅黑体'},range={applyCharacterStyle(s,clear){this.appliedCharacterStyle=s;this.clear=clear;}};
const doc={characterStyles:{itemByName:()=>({isValid:false})},allCharacterStyles:[style]};
context.JournalLayout.applyBiographyLabelStyle(doc,range);
assert.equal(range.appliedCharacterStyle,style);assert.equal(range.clear,false);
assert.throws(()=>context.JournalLayout.applyBiographyLabelStyle({characterStyles:doc.characterStyles,allCharacterStyles:[]},range),/BIO_CHARACTER_STYLE/);
console.log('PASS fixed received separator contract and exact existing biography character style');
for(const baseline of [255.424348962778,246.252126740556]){
  const page={id:1},other={id:2},separator={label:'article-footer-separator',parentPage:page,geometricBounds:[200,14.5,200,61.5]};
  const unrelated={label:'article-footer-separator',parentPage:other,geometricBounds:[180,14.5,180,61.5]};
  const guides=[{label:'spacing-guide-top',parentPage:page,geometricBounds:[100,14.5,108.75,100]},
    {label:'spacing-guide-footer',parentPage:page,geometricBounds:[194.5,14.5,200,100]}];
  const first={geometricBounds:[110,14.5,190,100]},footer={parentPage:page,lines:[{baseline}]};
  const doi={extractLabel:()=> 'doi',contents:''},body={extractLabel:()=> 'body',paragraphs:[],textContainers:[first]},
    received={extractLabel:()=> 'footer',textContainers:[footer]};
  const document={stories:[doi,body,received],allPageItems:[separator,...guides,unrelated],recompose(){}};
  context.JournalLayout.repairTemplateDetails(document,{doiContract:{text:'DOI:preserved-placeholder'},receivedSeparatorBaselineGapMm:4.8965711806});
  assert.equal(doi.contents,'DOI:preserved-placeholder');
  assert.ok(Math.abs(baseline-separator.geometricBounds[0]-4.8965711806)<1e-10);
  assert.equal(guides[1].geometricBounds[2],separator.geometricBounds[0]);
  assert.ok(first.geometricBounds[2]>190,'restore body capacity instead of leaving the previously shortened frame');
  assert.deepEqual(unrelated.geometricBounds,[180,14.5,180,61.5]);
}
