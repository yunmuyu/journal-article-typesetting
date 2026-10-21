const fs=require('node:fs');
const vm=require('node:vm');
const assert=require('node:assert/strict');
const source=fs.readFileSync(require('node:path').join(__dirname,'../2-导入_InDesign/seed_issue_article_pages.jsx'),'utf8');
const preferences={userInteractionLevel:1,enableRedraw:true};
const result=vm.runInNewContext(source,{
  JournalSeedJob:{path:'fixture_QA.indd'},File:x=>({fsName:x}),
  UserInteractionLevels:{NEVER_INTERACT:0},SaveOptions:{NO:0},
  app:{documents:[],scriptPreferences:preferences,open(){throw Error('FIXTURE_OPEN_FAILURE');}}
});
assert.equal(typeof result,'string','Native diagnostics must reach PowerShell');
assert.match(result,/FIXTURE_OPEN_FAILURE/);
assert.equal(preferences.userInteractionLevel,1);
assert.equal(preferences.enableRedraw,true);
console.log('PASS seed failure returns diagnostics and restores application preferences');
let written='';
let closed=false;
const fileContext={
  JournalSeedJob:{path:'fixture_QA.indd',referencePages:[5],resultPath:'result.txt'},
  File:x=>({fsName:x,open(){return true;},write(text){written=text;},close(){}}),
  UserInteractionLevels:{NEVER_INTERACT:0},SaveOptions:{NO:0},
  app:{documents:[],scriptPreferences:{userInteractionLevel:1,enableRedraw:true},open(){return {modified:false,pages:[{}],close(){closed=true;}};}}
};
const fileResult=vm.runInNewContext(source,fileContext);
assert.equal(fileResult,written,'File and return channels must agree');
assert.match(written,/^BEFORE 1\nERROR /,'PowerShell requires real newline delimiters');
assert.equal(closed,true,'Owned document closes on range failure');
console.log('PASS result file uses real newline records and closes owned document on failure');
