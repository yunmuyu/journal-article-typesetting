const assert=require('assert/strict'),{candidate}=require('../2-导入_InDesign/journal_table_fold.cjs');
const source=[['轮次','1','2','3','4','5','6','7','8','9','10','平均'],['时延/s','2.481','2.377','2.498','2.466','2.546','2.616','2.608','2.528','2.511','2.520','2.515']];
const p=candidate(source,{columnsPerBlock:6});assert.equal(p.rows.length,4);assert.equal(p.rows[2][0],'轮次');assert.equal(p.rows[3][5],'2.515');assert.equal(p.rows[3][6],'');
for(let row=0;row<2;row++)for(let col=1;col<source[row].length;col++){
 const found=[];p.sourceCells.forEach((maps,r)=>maps.forEach((m,c)=>{if(m?.row===row&&m.column===col)found.push(p.rows[r][c]);}));assert.deepEqual(found,[source[row][col]]);
}
assert.equal(candidate(source,{columnsPerBlock:6,merged:true}).status,'ineligible');assert.equal(p.automaticAssemblyApproved,false);assert.equal(p.fontSizePt,9);
console.log('PASS single-column folded table candidate preserves each data cell exactly once; repeated labels and padding mapped');
