const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const script = fs.readFileSync(require('node:path').join(__dirname, '..', '2-导入_InDesign', 'repair_formula_assets.jsx'), 'utf8');
const source = 'C:/fixture/input/formula-1.wmf';
const closed = [];
const file = path => ({fsName: path, open(){}, write(){}, close(){}});
const owned = {
  fullName: file(source),
  textFrames: [], pageItems: [], visibleBounds: [0, 10, 10, 0],
  artboards: [{}],
  groupItems: {add(){return {resize(){}};}},
  saveAs(path){this.fullName = path;},
  close(){closed.push(this);}
};
const frame = {
  contents: 'x', characters: [{contents:'x',characterAttributes:{size:10.5,textFont:{name:'TimesNewRomanPSMT'}}}],
  createOutline(){owned.textFrames=[];return {pageItems:[]};}
};
owned.textFrames=[frame];
const user = {fullName:file('C:/fixture/user-owned.ai'),close(){throw Error('USER_DOCUMENT_TOUCHED');}};
const app = {documents:[user],textFonts:{getByName(){return {name:'SimSun'};}},open(){this.documents.push(owned);return owned;}};
const context = vm.createContext({
  app, File:file, Folder: path=>({fsName:path,exists:true}),
  IllustratorSaveOptions:function(){}, SaveOptions:{DONOTSAVECHANGES:0},
  ElementPlacement:{PLACEATBEGINNING:0},Transformation:{TOPLEFT:0},
  JournalFormulaJob:{number:1,inputDirectory:'C:/fixture/input',outputDirectory:'C:/fixture/output',exportPdf:false,exportPng:false}
});
vm.runInContext(script,context);
assert.equal(closed.length,1,'Successful saveAs changes fullName: the owned Illustrator document must still close');
assert.equal(closed[0],owned);
console.log('PASS successful AI save closes owned document after its path changes');

closed.length=0;
owned.fullName=file(source);
app.documents=[user];
const greekAttributes={size:10.5,textFont:{name:'TimesNewRomanPS-BoldItalicMT',family:'Times New Roman'}};
const greekCharacters=[{contents:'a',characterAttributes:greekAttributes},{contents:'Ó',characterAttributes:greekAttributes}];
const greekFrame={
  get contents(){return greekCharacters.map(ch=>ch.contents).join('');},
  characters:greekCharacters,
  createOutline(){
    assert.equal(this.contents,'ΣÓ','only the source-identified character is repaired before outlining');
    owned.textFrames=[];
    return {pageItems:[]};
  }
};
owned.textFrames=[greekFrame];
context.JournalFormulaJob.greekRepairs=[{token:'a',text:'Σ',fontFamily:'Times New Roman',count:1}];
vm.runInContext(script,context);
assert.equal(closed.length,1);
assert.equal(greekCharacters[0].characterAttributes.textFont.name,'TimesNewRomanPS-BoldItalicMT');

owned.fullName=file(source);
app.documents=[user];
owned.textFrames=[greekFrame];
greekCharacters[0].contents='a';
greekCharacters[1].contents='a';
assert.throws(()=>vm.runInContext(script,context),/WMF_GREEK_IMPORT_COUNT/);
assert.equal(greekFrame.contents,'aa','ambiguous tokens are rejected before any character is changed');
context.JournalFormulaJob.greekRepairs=[];
console.log('PASS source-bound Greek text repair preserves a genuine Latin character and fails closed on duplicate tokens');

closed.length=0;
owned.fullName=file(source);
app.documents=[user,owned];
assert.throws(()=>vm.runInContext(script,context),/FORMULA_SOURCE_ALREADY_OPEN/);
assert.equal(closed.length,0, 'Pre-opened source WMF must stay open');
console.log('PASS source WMF already open is rejected without closing user documents');
