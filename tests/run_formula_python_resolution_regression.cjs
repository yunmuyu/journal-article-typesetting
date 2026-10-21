const cp=require('node:child_process'),p=require('node:path'),assert=require('node:assert/strict');
const r=cp.spawnSync('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',p.join(__dirname,'run_formula_python_resolution_regression.ps1')],{encoding:'utf8'});
assert.equal(r.status,0,r.stdout+r.stderr);process.stdout.write(r.stdout);
