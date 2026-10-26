const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const source=fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_article_assembly.jsxinc'),'utf8');
function fixture(kind='ordinary'){
  const files={logical:{blocks:[{role:'table_gap',text:'   ',runs:[],tableNumber:1}]},
    supplement:{tables:[{rows:[['synthetic']]}]},
    structure:{tables:[{rows:[[{start:0,span:1}]],widths:[1]}]},
    audit:{tableKinds:[{number:1,kind,reviewEvidence:'synthetic review',sourceEvidence:{}}]}};
  const job={logicalArticlePath:'logical',supplementPath:'supplement',tableStructurePath:'structure',auditConfigPath:'audit',
    panels:[],tables:[{number:1,sourceIndex:0,blockIndex:0,kind,reviewEvidence:'synthetic review',sourceEvidence:{}}],expected:{tables:1},outputPath:'candidate'};
  const calls=[];
  const document={id:42,isValid:true,preflightOptions:{preflightOff:false},viewPreferences:{},allPageItems:[],
    extractLabel(){return 'template-v1';},close(option){calls.push(['document.close',option]);this.isValid=false;}};
  const context=vm.createContext({
    File:p=>({open(){return true;},read(){return JSON.stringify(files[p]);},close(){}}),
    JournalDocumentSession:{acquire(){calls.push(['acquire']);return {document,openedHere:true};},
      save(){calls.push(['save']);},close(d,state,option){calls.push(['session.close',option]);d.close(option);state.closed=true;}},
    SaveOptions:{NO:'discard'},UserInteractionLevels:{NEVER_INTERACT:0},
    Justification:{CENTER_ALIGN:'center',RIGHT_ALIGN:'right'},VerticalJustification:{CENTER_ALIGN:'middle'},
    RulerOrigin:{PAGE_ORIGIN:0},MeasurementUnits:{MILLIMETERS:0}
  });
  vm.runInContext(source,context);
  vm.runInContext(fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_layout_rules.jsxinc'),'utf8'),context);
  return {files,job,calls,context,app:{scriptPreferences:{enableRedraw:true,userInteractionLevel:1}}};
}
for(const kind of ['unclassified','algorithm','three-line']){
  const f=fixture(kind);
  assert.throws(()=>f.context.JournalArticleAssembly.run(f.app,f.job),/TABLE_KIND_UNSUPPORTED/);
  assert.deepEqual(f.calls,[],'unapproved kinds cannot acquire or write a document');
}
for(const breakConfig of [f=>{f.files.audit.tableKinds[0].kind='algorithm';},
  f=>{f.job.tables[0].blockIndex=2;},f=>{f.files.supplement.tables=[];},
  f=>{f.files.audit.tableKinds[0].sourceEvidence={border:'none'};}]){
  const f=fixture();breakConfig(f);
  assert.throws(()=>f.context.JournalArticleAssembly.run(f.app,f.job),/TABLE_CONFIG_/);
  assert.deepEqual(f.calls,[],'inconsistent table configuration cannot acquire a document');
}
const decimal=fixture();
decimal.files.supplement.tables[0].rows=[['1.2'],['12.3']];
decimal.files.structure.tables[0].rows=[[{start:0,span:1}],[{start:0,span:1}]];
assert.throws(()=>decimal.context.JournalArticleAssembly.run(decimal.app,decimal.job),/TABLE_DECIMAL_ALIGNMENT_REVIEW_REQUIRED/);
assert.deepEqual(decimal.calls,[],'variable-shape decimal columns block before opening the document');
decimal.files.supplement.tables[0].rows.push(['12']);
decimal.files.structure.tables[0].rows.push([{start:0,span:1}]);
assert.throws(()=>decimal.context.JournalArticleAssembly.run(decimal.app,decimal.job),/TABLE_DECIMAL_ALIGNMENT_REVIEW_REQUIRED/);
assert.deepEqual(decimal.calls,[],'an integer mixed into a decimal column remains a zero-write blocker');
const failed=fixture();failed.job.templateContractVersion='template-v1';
const result=failed.context.JournalArticleAssembly.run(failed.app,failed.job);
assert.equal(result.status,'failed');
assert.match(result.failure,/SLOT_COUNT/);
assert.deepEqual(failed.calls,[['acquire'],['session.close','discard'],['document.close','discard']],
  'a failure after document mutation discards the candidate without saving');
console.log('PASS table preflight is zero-write and failed assembly discards its document');
for(const approved of [4.6,4.8,5.5]){
  const f=fixture();f.files.bottom={columns:[{adjustments:[]}]};f.job.bottomPlanPath='bottom';
  f.job.continuation={documentId:42};
  const cell={texts:[{justification:'left',lines:[{}]}],properties:{}};
  const table={label:'source-table-1',rows:[{minimumHeight:5,height:approved,autoGrow:true,cells:[cell]}],cells:[cell],columns:[{width:85.5}]};
  const story={tables:[table],extractLabel(){return 'body';}};
  const document=f.context.JournalDocumentSession.acquire(f.app,f.job.outputPath).document;
  f.calls.length=0;document.stories=[story];document.insertLabel=()=>{};
  f.context.Justification={CENTER_ALIGN:'center'};f.context.VerticalJustification={CENTER_ALIGN:'middle'};
  vm.runInContext(fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_layout_rules.jsxinc'),'utf8'),f.context);
  f.context.JournalLayout.alignLocalBlocks=()=>{};
  f.context.JournalBottomPlan={apply(){table.rows[0].minimumHeight=approved;return {};}};
  const applied=f.context.JournalArticleAssembly.applyBottomExisting(f.app,f.job);
  assert.equal(applied.status,'bottom-applied-unchecked');
  assert.equal(table.rows[0].minimumHeight,approved,'bottom-plan minimum survives the complete apply stage');
  assert.deepEqual(f.calls,[['acquire'],['save']]);
  f.files.reflow={};f.job.reflowPlanPath='reflow';f.calls.length=0;
  f.context.JournalReflow={apply(){table.rows[0].minimumHeight=approved;return {};}};
  const reflowed=f.context.JournalArticleAssembly.reflowExisting(f.app,f.job);
  assert.equal(reflowed.status,'reflowed-unchecked');
  assert.equal(table.rows[0].minimumHeight,approved,'approved minimum survives the complete reflow stage');
  assert.deepEqual(f.calls,[['acquire'],['save']]);
}
console.log('PASS approved 4.6/4.8/5.5 mm table minima survive bottom-plan and reflow stages');
