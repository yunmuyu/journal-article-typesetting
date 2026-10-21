const cp=require('node:child_process'),path=require('node:path'),assert=require('node:assert/strict');
const script=path.join(__dirname,'local_bottom_attempt_benchmark.cjs');
function measure(args){const r=cp.spawnSync(process.execPath,[script,...args],{encoding:'utf8',windowsHide:true});assert.equal(r.status,0,r.stderr);return JSON.parse(r.stdout);}
const before=measure(['--baseline']),after=measure([]);
assert.equal(after.bottom,before.bottom);assert.equal(after.lines,before.lines);assert.equal(after.end,before.end);assert.ok(after.recompositions<before.recompositions);
const boundary=cp.spawnSync(process.execPath,[path.join(__dirname,'bottom_interval_behavior_regression.js')],{encoding:'utf8',windowsHide:true});assert.equal(boundary.status,0,boundary.stderr);
console.log('PASS fixed target avoids duplicate trials; exact bottom, endpoint, rollback and local interval behavior retained');
