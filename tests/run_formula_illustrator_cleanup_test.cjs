// Behaviour check for repair_formula_assets.jsx document ownership.
// Illustrator documents have no InDesign-style isValid contract, so cleanup is
// verified by running the script against a mocked app and observing exactly which
// document gets closed on the failure path.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(path.join(__dirname,'..','2-导入_InDesign','repair_formula_assets.jsx'),'utf8');
const outputDirectory='C:/work/stage';
const sourcePath='C:/work/input/formula-5.wmf';
const closed=[],written=[];
function makeFile(name){
  return {fsName:name,exists:true,open(){return this;},write(t){written.push(t);},close(){},toString(){return name;}};
}
const opened={archboards:[{artboardRect:[0,0,1,1]}],artboards:[{artboardRect:[0,0,1,1]}],textFrames:[],pageItems:[],groupItems:{add(){return {pageItems:[],move(){}};}},visibleBounds:[0,0,1,1],name:'formula-5.wmf',fullName:makeFile(sourcePath),close(){closed.push(sourcePath);}};
const preopened={fullName:makeFile('C:/work/designs/existing.ai'),close(){closed.push('C:/work/designs/existing.ai');}};
const untitled={get fullName(){throw Error('DOCUMENT_HAS_NO_FILE');},close(){closed.push('UNTITLED');}};
const app={textFonts:{getByName(){return {name:'SimSun'};}},documents:[preopened,untitled],open(){this.documents.push(opened);return opened;}};
const context={app,JournalFormulaJob:{number:5,inputDirectory:'C:/work/input',outputDirectory},File:makeFile,Folder:name=>({exists:true,create(){return true;},fsName:name}),SaveOptions:{DONOTSAVECHANGES:2},Error,Math,String,Number,Array};
vm.createContext(context);
// Illustrator scripts run on ExtendScript (ES3): no Array.prototype.indexOf,
// Array.prototype.forEach, Object.keys or JSON helpers. Removing the modern array
// search from the sandbox keeps the check honest.
delete context.Array.prototype.indexOf;
assert.throws(()=>vm.runInContext(source,context),/SOURCE_FORMULA_SIZE_UNRESOLVED/);
assert.deepEqual(closed,[sourcePath],'only the document opened by this call may be closed');
assert.equal(written.length,1,'failure diagnostic is still written');
assert.ok(written[0].includes('SOURCE_FORMULA_SIZE_UNRESOLVED'),'diagnostic names the unresolved size');
console.log('PASS formula repair closes exactly its owned document on failure and leaves pre-opened and untitled documents alone');
