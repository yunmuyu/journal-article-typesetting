const fs=require('node:fs');
function build(measurement,bottom,maxPerColumn=24){
 if(!Number.isInteger(maxPerColumn)||maxPerColumn<1||maxPerColumn>24)throw Error("TRACKING_REQUEST_BUDGET");
 const selected=new Map();
 for(const column of bottom.columns||[]){
  if(column.status!=='blocked')continue;
  const id=Number(column.id);
  const frame=measurement.frames.find(f=>f.id===id),ids=new Set([id]);
  if(frame&&frame.index>=0)for(const other of measurement.frames)if(other.index>=frame.index)ids.add(other.id);
  if(frame)for(const other of measurement.frames)if(Math.abs(other.index-frame.index)===1&&other.pageIndex===frame.pageIndex&&Math.abs(other.targetBottomMm-frame.targetBottomMm)<.01)ids.add(other.id);
  for(const p of measurement.paragraphs.filter(p=>['body','reference','bio'].includes(p.role)&&(ids.has(p.firstFrameId)&&ids.has(p.lastFrameId)||frame&&p.lastFrameId===id&&measurement.frames.some(f=>f.id===p.firstFrameId&&f.index===frame.index-1&&f.pageIndex===frame.pageIndex))&&(!frame||measurement.frames.find(f=>f.id===p.firstFrameId)?.index<=frame.index)&&p.text.length>35).sort((a,b)=>b.text.length-a.text.length).slice(0,maxPerColumn))selected.set(p.start,{start:p.start,text:p.text});
 }
 for(const pair of bottom.deferred||[])if(pair.kind==='local-pair'||pair.kind==='final-pair'){
  const ids=new Set(pair.frames.map(i=>measurement.frames[i].id));
  for(const p of measurement.paragraphs.filter(p=>['body','reference','bio'].includes(p.role)&&ids.has(p.firstFrameId)&&ids.has(p.lastFrameId)&&p.text.length>35).slice(-6))selected.set(p.start,{start:p.start,text:p.text});
 }
 return [...selected.values()];
}
if(require.main===module){const [m,b,out,budget]=process.argv.slice(2),read=f=>JSON.parse(fs.readFileSync(f,'utf8').replace(/^\uFEFF/,''));const requests=build(read(m),read(b),budget===undefined?24:Number(budget));fs.writeFileSync(out,JSON.stringify(requests,null,2));console.log(JSON.stringify({requests:requests.length}));}
module.exports={build};
