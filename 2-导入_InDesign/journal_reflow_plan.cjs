const fs=require('node:fs');
const {tableRows,localPairBandTop}=require('./journal_bottom_measurement_request.cjs');
function trackingChoices(m,bottom){
 const probes=m.trackingProbes||[],decisions=[],choices=[],targets=[];
 if(probes.length&&(!m.flowSignature||probes.some(p=>p.probeVersion!==2)))throw Error('TRACKING_PROBE_STALE');
 for(const column of bottom.columns||[])if(column.status==='blocked'){
  const frame=m.frames.find(f=>String(f.id)===column.id);
  if(frame)targets.push({id:'column:'+frame.id,frames:[frame],measure:Number.isFinite(frame.targetInkBottomMm)?'ink':'baseline',targetMm:frame.targetInkBottomMm??frame.targetBottomMm});
  if(frame){
   const at=m.frames.indexOf(frame);
   if(at>=0)targets.push({id:'flow:'+frame.id,frames:m.frames.slice(at),measure:'baseline',flowSuffix:true});
   for(const other of [m.frames[at-1],m.frames[at+1]])if(other&&other.pageIndex===frame.pageIndex&&Math.abs(other.targetBottomMm-frame.targetBottomMm)<.01){
    const frames=[frame,other].sort((a,b)=>a.index-b.index);
    if(!targets.some(t=>t.id==='columns:'+frames.map(f=>f.id).join(',')))targets.push({id:'columns:'+frames.map(f=>f.id).join(','),frames,measure:'baseline',individualTargets:true});
   }
  }
 }
 for(const pair of bottom.deferred||[])if(pair.kind==='local-pair'||pair.kind==='final-pair')
  targets.push({id:pair.kind+':'+pair.frames.join(','),frames:pair.frames.map(i=>m.frames[i]),
   measure:pair.kind==='final-pair'?'baseline':'ink',ceilingMm:pair.kind==='local-pair'?localPairBandTop(m,m.frames[pair.frames[0]],m.frames[pair.frames[1]])-.2:undefined});
 function interval(frame,state,measure,availableCeiling){
  if(Number.isFinite(frame.targetInkBottomMm))measure='ink';
  const rows=tableRows(frame,m),value=measure==='ink'?state.inkBottomMm:state.bottomMm;
  const ceiling=(Number.isFinite(availableCeiling)?availableCeiling:frame.bounds[2])-(measure==='baseline'?Math.max(0,state.inkBottomMm-state.bottomMm):0)-.03;
  return [value-state.leadingDownMm-rows.reduce((s,r)=>s+r.currentHeightMm-r.minHeightMm,0),
   Math.min(ceiling,value+state.leadingUpMm+rows.reduce((s,r)=>s+r.maxHeightMm-r.currentHeightMm,0))];
 }
 function endpointSame(a,b){return JSON.stringify(a)===JSON.stringify(b);}
 function evaluate(p,o,t){
  const paragraph=m.paragraphs.find(q=>q.start===p.start),ids=new Set(t.frames.map(f=>f.id));
  if(!paragraph||!ids.has(paragraph.firstFrameId)||!ids.has(paragraph.lastFrameId))return 'OUTSIDE_TARGET';
  const states=t.frames.map(f=>o.frames.find(s=>s.id===f.id));
  if(states.some(s=>!s))return 'MEASUREMENT_INCOMPLETE';
  // Natural continuation within a pair is allowed; the combined text and all other columns stay fixed.
  for(const f of m.frames){
   const after=o.frames.find(s=>s.id===f.id);
   if(!after)return 'MEASUREMENT_INCOMPLETE';
   if(!ids.has(f.id)&&!endpointSame(after.endpoint,f.endpoint))return 'FLOW_OUTSIDE_TARGET';
  }
  if(states[0].endpoint?.[0]!==t.frames[0].endpoint?.[0]||
   states.filter(s=>s.endpoint).at(-1)?.endpoint?.[1]!==t.frames.filter(f=>f.endpoint).at(-1)?.endpoint?.[1])return 'TARGET_TEXT_CHANGED';
  const ranges=t.frames.map((f,i)=>interval(f,states[i],t.measure,t.ceilingMm));
  const low=Math.max(...ranges.map(r=>r[0])),high=Math.min(...ranges.map(r=>r[1]));
  function progress(){
   if(!p.currentFrames)return 'CAPACITY_STILL_INFEASIBLE';
   const oldStates=t.frames.map(f=>p.currentFrames.find(s=>s.id===f.id));if(oldStates.some(s=>!s))return 'CAPACITY_STILL_INFEASIBLE';
   const oldRanges=t.frames.map((f,i)=>interval(f,oldStates[i],t.measure,t.ceilingMm));
   const distance=(target,r)=>Math.max(0,r[0]-target,target-r[1]);
   let before=0,after=0;
   for(let i=0;i<t.frames.length;i++){
    const target=t.frames.length===1?t.targetMm:(t.frames[i].targetInkBottomMm??t.frames[i].targetBottomMm),a=distance(target,oldRanges[i]),b=distance(target,ranges[i]);
    if(a<=.003&&b>.003)return 'CAPACITY_STILL_INFEASIBLE';before+=a;after+=b;
   }
   return before>.003&&after<before-.003?'CAPACITY_PROGRESS':'CAPACITY_STILL_INFEASIBLE';
  }
  if(t.flowSuffix){
   const lastPage=Math.max(...t.frames.map(f=>f.pageIndex));
   for(let i=0;i<t.frames.length;i++)if(t.frames[i].pageIndex!==lastPage){const r=ranges[i],target=t.frames[i].targetBottomMm;if(target<r[0]-.003||target>r[1]+.003)return 'CAPACITY_STILL_INFEASIBLE';}
   const final=ranges.filter((r,i)=>t.frames[i].pageIndex===lastPage);
   if(o.finalPageExpansion)return null;
   if(final.length!==2||Math.max(...final.map(r=>r[0]))>Math.min(...final.map(r=>r[1]))+.003)return 'CAPACITY_STILL_INFEASIBLE';
   return null;
  }
  if(t.individualTargets)return ranges.every((r,i)=>t.frames[i].targetBottomMm>=r[0]-.003&&t.frames[i].targetBottomMm<=r[1]+.003)?null:progress();
  if(t.frames.length===1)return t.targetMm>=low-.003&&t.targetMm<=high+.003?null:progress();
  return low<=high+.003?null:'CAPACITY_STILL_INFEASIBLE';
 }
 for(const p of probes)for(const o of p.outcomes){
  const decision={start:p.start,tracking:o.tracking,lineDelta:o.currentLineDelta,targets:[]};
  if(o.tracking===p.currentTracking){decision.reason='ALREADY_CURRENT';}
  else if(Math.abs(o.tracking)>20){decision.reason='TRACKING_LIMIT';}
  else if(!o.orphanFree||!o.tokenBreakFree||o.overflows){decision.reason='ORPHAN_TOKEN_OR_OVERFLOW';}
  else if(Math.abs(o.currentLineDelta)!==1){decision.reason='NO_ONE_LINE_CHANGE';}
  else{
   for(const target of targets){
    const reason=evaluate(p,o,target);decision.targets.push({id:target.id,reason:reason||'FEASIBLE'});
    if(!reason||reason==='CAPACITY_PROGRESS')choices.push({start:p.start,text:p.text,tracking:o.tracking,currentTracking:p.currentTracking,
     expectedLineCount:o.lineCount,context:p.context,frames:o.frames,finalPageExpansion:o.finalPageExpansion===true,
     target:target.id,capacityProgress:reason==='CAPACITY_PROGRESS',frameIds:target.frames.map(f=>f.id),purpose:o.currentLineDelta<0?'one-fewer-line':'one-extra-line'});
   }
   decision.reason=decision.targets.some(t=>t.reason==='FEASIBLE'||t.reason==='CAPACITY_PROGRESS')?'FEASIBLE':
    decision.targets.some(t=>t.reason!=='OUTSIDE_TARGET')?'LAYOUT_CONSTRAINT':'NO_BLOCKED_TARGET';
  }
  decisions.push(decision);
 }
 choices.sort((a,b)=>Number(a.capacityProgress)-Number(b.capacityProgress)||Math.abs(a.tracking-a.currentTracking)-Math.abs(b.tracking-b.currentTracking)||
  Math.abs(a.tracking)-Math.abs(b.tracking));
 const selected=[],usedFrames=new Set(),usedParagraphs=new Set();
 for(const choice of choices){
  if(usedParagraphs.has(choice.start)||choice.frameIds.some(id=>usedFrames.has(id)))continue;
  selected.push(choice);usedParagraphs.add(choice.start);choice.frameIds.forEach(id=>usedFrames.add(id));
 }
 for(const decision of decisions)if(decision.reason==='FEASIBLE')
  decision.reason=selected.some(c=>c.start===decision.start&&c.tracking===decision.tracking)?'SELECTED':'SMALLER_FEASIBLE_ADJUSTMENT';
 return {selected,decisions};
}
function lastPageCandidates(m){
 const page=Math.max(...m.frames.map(f=>f.pageIndex)),frames=m.frames.filter(f=>f.pageIndex===page);
 if(frames.length!==2)throw Error('FINAL_PAGE_REQUIRES_TWO_COLUMNS');
 const lines=[],left=frames[0],right=frames[1];
 let offset=0,previous=null;
 for(const frame of frames){
  if(!frame.lines.length)continue;
  if(previous)offset=previous.global+frame.lines[0].leading*25.4/72-frame.lines[0].baseline;
  for(const line of frame.lines){const record={...line,global:line.baseline+offset};lines.push(record);previous=record;}
 }
 const result=[];
 for(const paragraph of m.paragraphs){
  if(paragraph.start<=left.endpoint[0])continue;
  const at=lines.findIndex(l=>l.start===paragraph.start);
  if(at<=0)continue;
  const before=m.paragraphs.find(p=>p.start===lines[at-1].paragraphStart);
  if(!['body','reference','bio'].includes(paragraph.role)&&!(paragraph.role==='h2'&&before?.role==='h1'))continue;
  if(before?.keepWithNext>0||['h2','referenceTitle'].includes(before?.role))continue;
  const leftBottom=lines[at-1].global;
  const rightBottom=lines.at(-1).global-lines[at].global+right.bounds[0]+lines[at].ascent;
  if(leftBottom>left.bounds[2]||rightBottom>right.bounds[2])continue;
  result.push({start:paragraph.start,text:paragraph.text,estimatedLeftMm:leftBottom,estimatedRightMm:rightBottom,
    imbalanceMm:Math.abs(leftBottom-rightBottom)});
 }
 return result.sort((a,b)=>a.imbalanceMm-b.imbalanceMm).slice(0,3);
}
function lastPageBalance(m){
 const page=Math.max(...m.frames.map(f=>f.pageIndex)),frames=m.frames.filter(f=>f.pageIndex===page);
 if(frames.length!==2||frames.every(f=>!f.lines.length))throw Error('FINAL_PAGE_REQUIRES_TWO_COLUMNS_WITH_CONTENT');
 return {frameIds:frames.map(f=>f.id),topMm:Math.max(...frames.map(f=>f.bounds[0])),
   maximumBottomMm:Math.max(...m.frames.map(f=>f.bounds[2])),allowNormalParagraphContinuation:true};
}
function build(m,bottom){
 const tracking=trackingChoices(m,bottom);
 const leadingCompression=[];
 for(const column of bottom.columns)if(column.status==='blocked'){
  const at=m.frames.findIndex(f=>String(f.id)===column.id),frame=m.frames[at],next=m.frames[at+1];
  if(!next?.lines.length||!frame?.lines.length)continue;
  const incoming=next.lines[0],last=frame.lines.at(-1);
  if(incoming.adjustableLeading===false||!['body','reference','bio'].includes(incoming.role)||incoming.paragraphStart!==last.paragraphStart||last.role!==incoming.role)continue;
  const minimum=l=>['reference','bio'].includes(l.role)?12.6:14.8;
  const maximum=l=>['reference','bio'].includes(l.role)?13.4:16;
  const ink=Number.isFinite(frame.targetInkBottomMm);
  const eligible=(ink?frame.lines:frame.lines.slice(1)).concat(incoming).filter(l=>l.adjustableLeading!==false&&(ink?['body','h1','h2','reference','bio']:['body','reference','bio']).includes(l.role)&&!l.hasTable&&l.leading>=minimum(l)&&l.leading<=maximum(l));
  const needed=((ink?frame.inkBottomMm:frame.bottomMm)+incoming.leading*25.4/72-(ink?frame.targetInkBottomMm:frame.targetBottomMm))*72/25.4;
  const capacity=eligible.reduce((s,l)=>s+l.leading-minimum(l),0);
  if(needed<=0||needed>capacity)continue;
  for(const line of eligible)leadingCompression.push({start:line.start,end:line.end,text:line.text,role:line.role,leading:ink?Math.max(minimum(line),line.leading-needed/capacity*(line.leading-minimum(line))):minimum(line)});
 }
 const leadingExpansion=[],leadingTransfers=[];
 if(!tracking.selected.length&&!leadingCompression.length&&!(bottom.deferred||[]).some(p=>p.kind==='final-pair'))for(const column of bottom.columns||[])if(column.status==='blocked'&&column.requiredDeltaPt>0){
  const at=m.frames.findIndex(f=>String(f.id)===column.id),receiver=m.frames[at],donor=m.frames[at-1];
  if(!donor||donor.pageIndex!==receiver.pageIndex||Math.abs(donor.bounds[0]-receiver.bounds[0])>.03||Math.abs(donor.bounds[2]-receiver.bounds[2])>.03||Math.abs(donor.targetBottomMm-receiver.targetBottomMm)>.03)continue;
  if(!bottom.columns.some(c=>c.id===String(donor.id)&&c.status==='ready'))continue;
  const eligible=donor.lines.slice(0,-1).filter(l=>l.adjustableLeading!==false&&l.role==='body'&&!l.hasTable&&l.leading>=14.8&&l.leading<16&&typeof l.text==='string');
  if(!eligible.length||donor.lines.at(-1)?.role!=='body')continue;
  const forcePt=Math.max(0,(donor.bounds[2]-(donor.lines.at(-1).descent||.05)-donor.bottomMm+.03)*72/25.4);
  const step=Math.max(.025,forcePt/eligible.length);
  for(const line of eligible)leadingExpansion.push({start:line.start,end:line.end,text:line.text,role:'body',leading:Math.min(16,line.leading+step)});
  leadingTransfers.push({fromFrameId:donor.id,toFrameId:receiver.id,stepPt:step});break;
 }
 return {schemaVersion:1,documentId:m.documentId,storyId:m.storyId,flowSignature:m.flowSignature,
  leadingCompression,leadingExpansion,leadingTransfers,
  tracking:tracking.selected,trackingDecisions:tracking.decisions,lastPageCandidates:lastPageCandidates(m),
  lastPageBalance:lastPageBalance(m),
  limitation:'Estimated split must be composed and checked; no approval implied.'};
}
module.exports={build,lastPageCandidates,lastPageBalance,trackingChoices};
if(require.main===module){
 const [measuredPath,bottomPath,outputPath]=process.argv.slice(2);
 const read=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''));
 const result=build(read(measuredPath),read(bottomPath));
 fs.writeFileSync(outputPath,JSON.stringify(result,null,2)+'\n');
 console.log(JSON.stringify({tracking:result.tracking.map(x=>({start:x.start,value:x.tracking})),lastPageCandidates:result.lastPageCandidates.map(x=>({start:x.start,difference:x.imbalanceMm}))}));
}
