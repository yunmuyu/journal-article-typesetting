const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os'),cp=require('node:child_process'),vm=require('node:vm');
const tmp=path.resolve(os.tmpdir()),folder=fs.mkdtempSync(path.join(tmp,'journal-gap-entry-'));
try{
 const qa=path.join(folder,'fixture_QA.indd'),config=path.join(folder,'config.json'),report=path.join(folder,'receipt.json');fs.writeFileSync(qa,'synthetic');fs.writeFileSync(config,JSON.stringify({documentPath:qa,bindings:[{id:2,role:'body'}],articlePageRange:[0,0]}));
 const run=cp.spawnSync(process.env.JOURNAL_PWSH||'pwsh.exe',['-NoProfile','-File',path.resolve('2-导入_InDesign/Invoke-JournalGapStage.ps1'),'-ConfigPath',config,'-DocumentId','123','-ReportPath',report,'-PlanOnly'],{encoding:'utf8'});
 assert.equal(run.status,0,run.stdout+run.stderr);const plan=JSON.parse(run.stdout.replace(String.fromCharCode(65279),''));assert.equal(plan.adobeCalled,false);new vm.Script(fs.readFileSync(plan.codePath,'utf8'));assert(!fs.existsSync(report));assert.equal(fs.readFileSync(qa,'utf8'),'synthetic');console.log('PASS real PowerShell stage generates valid JavaScript without Adobe or document changes');
}finally{assert.equal(path.dirname(folder),tmp);assert(path.basename(folder).startsWith('journal-gap-entry-'));fs.rmSync(folder,{recursive:true});}
