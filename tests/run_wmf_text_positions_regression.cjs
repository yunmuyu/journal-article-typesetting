const p=require('path'),cp=require('child_process'),assert=require('node:assert/strict');
const result=cp.spawnSync(process.env.JOURNAL_PYTHON||'python',[p.join(__dirname,'test_wmf_text_positions.py')],{encoding:'utf8'});assert.equal(result.status,0,result.stdout+result.stderr);console.log(result.stdout.trim());
