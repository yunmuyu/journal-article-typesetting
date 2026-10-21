const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const digest=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
function synchronize(config,job,evidence,cacheRoot){
 const c=structuredClone(config),j=structuredClone(job),entries=[],changes=[];
 for(const contract of c.formulaCacheContract||[]){
  if(!/^[a-f0-9]{64}$/i.test(contract.cacheKey)||!/^[-a-z0-9]+$/i.test(contract.ruleVersion))throw Error('FORMULA_CACHE_ID');
  const rows=evidence.rows.filter(r=>r.number===contract.number);if(rows.length!==1)throw Error('FORMULA_MEASUREMENT_COUNT');const r=rows[0];
  if(r.cacheType!=='Group'||r.actualType!=='Group'||r.scaleX!==100||r.scaleY!==100||r.hashLabel!==contract.sha256||r.sha256!==contract.sha256||!Number.isFinite(r.cacheWidth)||!Number.isFinite(r.cacheHeight)||r.cacheWidth<=0||r.cacheHeight<=0||Math.abs(r.cacheWidth-r.actualWidth)>.02||Math.abs(r.cacheHeight-r.actualHeight)>.02)throw Error('FORMULA_MEASUREMENT_MISMATCH');
  const directory=path.join(cacheRoot,contract.ruleVersion,contract.cacheKey.slice(0,2),contract.cacheKey),record=JSON.parse(fs.readFileSync(path.join(directory,'asset.json'),'utf8').replace(/^\uFEFF/,''));
  if(record.rule?.basePointSize!==10.5||record.rule?.outlined!==true||record.rule?.version!==contract.ruleVersion||record.cacheKey!==contract.cacheKey||record.source.sha256!==contract.sourceSha256||record.artifacts.idms.sha256!==contract.sha256)throw Error('FORMULA_RECORD_MISMATCH');
  const idms=path.join(directory,'formula.idms'),ai=path.join(directory,'formula.ai');if(digest(idms)!==contract.sha256||digest(ai)!==record.artifacts.ai.sha256)throw Error('FORMULA_CACHE_HASH_CHANGED');
  const assets=c.assets.filter(a=>a.kind==='formula'&&a.number===contract.number);if(assets.length!==1)throw Error('FORMULA_ASSET_COUNT');const asset=assets[0];changes.push({number:contract.number,oldWidth:asset.width,oldHeight:asset.height,width:r.cacheWidth,height:r.cacheHeight,idmsSha256:contract.sha256});
  Object.assign(asset,{path:ai,name:'formula.ai',sha256:record.artifacts.ai.sha256,width:r.cacheWidth,height:r.cacheHeight,placement:'native-vector',basePointSize:10.5});
  const numbers=(c.formulaNumbers||[]).filter(n=>n.number===contract.number);if(numbers.length!==1)throw Error('FORMULA_NUMBER_CONTRACT');const n=numbers[0];entries.push({...contract,path:idms,basePointSize:10.5,inline:n.inline===true,displayNumber:n.displayNumber===null?null:String(n.displayNumber)});
 }
 if(!entries.length)throw Error('FORMULA_CONTRACT_EMPTY');j.formulas={mode:'native-idms',entries};j.inputs=(j.inputs||[]).filter(i=>!/^formula-[0-9]+$/.test(i.name)&&!/^native-formula-[0-9]+$/.test(i.name));for(const e of entries)j.inputs.push({name:'native-formula-'+e.number,path:e.path,sha256:e.sha256});
 return {config:c,job:j,changes};
}
module.exports={synchronize};
