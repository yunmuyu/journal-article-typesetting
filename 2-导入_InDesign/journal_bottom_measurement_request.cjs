const fs=require('node:fs');
const PT=72/25.4;
function groups(frame){
  return frame.lines.slice(0,-1).filter(line=>line.adjustableLeading!==false&&!line.hasTable&&(!('text' in line)||/[^\s\uFFFC]/.test(line.text))&&
    ['body','h1','h2','reference','bio'].includes(line.role)&&line.frameId===frame.id)
    .filter(line=>Number.isFinite(line.leading)&&line.leading>=(['reference','bio'].includes(line.role)?12.6:14.8)&&
      line.leading<=(['reference','bio'].includes(line.role)?13.4:16))
    .map(line=>({id:`${frame.id}:${line.start}`,kind:['reference','bio'].includes(line.role)?'reference':'body',
      currentPt:line.leading,minPt:['reference','bio'].includes(line.role)?12.6:14.8,maxPt:['reference','bio'].includes(line.role)?13.4:16,
      lineCount:1,baselineIntervals:1,target:{storyRole:'body',startIndex:line.start,endIndex:line.end-1}}));
}
function capacity(gs){
  return {down:gs.reduce((n,g)=>n+g.currentPt-g.minPt,0)/PT,
    up:gs.reduce((n,g)=>n+g.maxPt-g.currentPt,0)/PT};
}
function tableRows(frame,measurement){
 const result=[];
 for(const table of measurement.tables||[])for(const row of table.rows){
  if(row.index<table.headerRowCount||row.height>5.5001||row.height<4.5999)continue;
  const cells=table.cells.filter(c=>c.rowIndex===row.index&&c.rowSpan===1);
  if(!cells.length||cells.some(c=>c.lines.length!==1||c.lines[0].frameId!==frame.id))continue;
  result.push({id:`${table.id}:${row.index}`,singleLine:true,currentHeightMm:row.height,minHeightMm:4.6,maxHeightMm:5.5,
   target:{tableLabel:table.label,rowIndex:row.index}});
 }
 return result;
}
function localPairBandTop(measurement,a,b){
 const owned=new Set(measurement.frames.map(f=>f.id));
 return Math.min(...(measurement.figures||[]).filter(f=>f.pageIndex===a.pageIndex&&!owned.has(f.frameId)&&f.frameBounds?.[0]>=Math.max(a.bounds[2],b.bounds[2])-.01).map(f=>f.frameBounds[0]));
}
function build(measurement){
  if(measurement.schemaVersion!==1||measurement.overflows)throw Error('MEASUREMENT_NOT_COMPOSED');
  const columns=[],deferred=[],frameExpansions=[],local=new Map(),lastPage=Math.max(...measurement.frames.map(f=>f.pageIndex));
  const pairs=measurement.localBottomPairs.map(p=>({...p,measure:'ink'}));
  const final=measurement.frames.filter(f=>f.pageIndex===lastPage);
  if(final.length!==2)throw Error('FINAL_PAGE_REQUIRES_TWO_COLUMNS');
  pairs.push({frames:final.map(f=>f.index),measure:'baseline',final:true});
  function available(frame){
   const c=capacity(groups(frame)),rows=tableRows(frame,measurement);
   return {down:c.down+rows.reduce((n,r)=>n+r.currentHeightMm-r.minHeightMm,0),
    up:c.up+rows.reduce((n,r)=>n+r.maxHeightMm-r.currentHeightMm,0)};
  }
  for(const pair of pairs){
    const a=measurement.frames[pair.frames[0]],b=measurement.frames[pair.frames[1]];
    const bandTop=pair.final?null:localPairBandTop(measurement,a,b);
    const fullPageBottom=Math.max(...measurement.frames.map(f=>f.bounds[2]));
    const ceilingA=pair.final?fullPageBottom:Number.isFinite(bandTop)?bandTop-.2:a.bounds[2];
    const ceilingB=pair.final?fullPageBottom:Number.isFinite(bandTop)?bandTop-.2:b.bounds[2];
    const ca=available(a),cb=available(b),ab=pair.final?a.bottomMm:a.inkBottomMm,bb=pair.final?b.bottomMm:b.inkBottomMm;
    const low=Math.max(ab-ca.down,bb-cb.down);
    const high=Math.min(ab+ca.up,bb+cb.up,
      ceilingA-(pair.final?a.inkBottomMm-a.bottomMm:0)-.03,
      ceilingB-(pair.final?b.inkBottomMm-b.bottomMm:0)-.03);
    if(low>high+.003){
      deferred.push({kind:pair.final?'final-pair':'local-pair',frames:pair.frames,reason:'NO_ADJUSTMENT_CAPACITY_INTERSECTION',
        feasibleMm:[[ab-ca.down,ab+ca.up],[bb-cb.down,bb+cb.up]]});
      local.set(a.id,null);local.set(b.id,null);
    }else{
      const target=Math.max(low,Math.min(high,Math.max(ab,bb)));
      if(pair.final){
       for(const f of [a,b]){
        const required=Math.max(f.bounds[2],target+(f.lines.at(-1).descent||0)+.15);
        if(required>fullPageBottom)throw Error('FINAL_PAGE_BOTTOM_CAPACITY');
        if(required>f.bounds[2]+.003)frameExpansions.push({id:f.id,fromBounds:f.bounds,toBottomMm:required,maximumBottomMm:fullPageBottom});
       }
      }else{
       // Empty semantic markers still occupy composed space. Use existing whitespace before the
       // figure, without moving text-frame tops, the figure, or lower text frames.
       const required=[a,b].map(f=>{
        const tail=f.lines.at(-1),delta=target-f.inkBottomMm;
        return {frame:f,bottom:Math.max(f.bounds[2],target+.15,delta>.003&&tail?.text?.trim()===''?
         tail.baseline+(tail.descent||0)+delta+.15:f.bounds[2])};
       });
       if(required.some(r=>r.bottom>Math.min(ceilingA,ceilingB)+.003)){
        deferred.push({kind:'local-pair',frames:pair.frames,reason:'SEMANTIC_MARKER_CAPACITY'});
        local.set(a.id,null);local.set(b.id,null);continue;
       }
       for(const {frame:f,bottom} of required)if(bottom>f.bounds[2]+.003)frameExpansions.push({id:f.id,fromBounds:f.bounds,toBottomMm:bottom,maximumBottomMm:Math.min(ceilingA,ceilingB)});
      }
      local.set(a.id,{target,measure:pair.measure});local.set(b.id,{target,measure:pair.measure});
    }
  }
  for(const frame of measurement.frames){
    const metadata=frame.index===0&&Number.isFinite(frame.targetInkBottomMm);
    if(frame.index===0&&!metadata)continue;
    const isLocal=local.has(frame.id);
    if(isLocal&&local.get(frame.id)===null)continue;
    if(!metadata&&!isLocal&&frame.bounds[2]<264.9)continue;
    const measure=metadata?'ink':isLocal?local.get(frame.id).measure:'baseline';
    const current=measure==='ink'?frame.inkBottomMm:frame.bottomMm,target=metadata?frame.targetInkBottomMm:isLocal?local.get(frame.id).target:
      frame.targetBottomMm-(frame.lines.at(-1)?.role==='formula'?.005:0);
    columns.push({id:String(frame.id),frameIndex:frame.index,measure,
      currentBottomPt:current*PT,targetBottomPt:target*PT,
      leadingGroups:groups(frame),trackingCandidates:[],figures:[],tableRows:tableRows(frame,measurement)});
  }
  return {version:1,tolerancePt:.01,columns,deferred,frameExpansions,
    preservation:{required:true,documentId:measurement.documentId,storyId:measurement.storyId,
      frames:measurement.frames.map(f=>({id:f.id,endpoint:f.endpoint,lineCount:f.lines.length})),
      tables:(measurement.tables||[]).map(t=>({label:t.label,rows:t.rows.filter(r=>r.index>=t.headerRowCount).map(r=>{
       const c=t.cells.find(c=>c.rowIndex===r.index&&c.rowSpan===1&&c.lines.length);
       return {rowIndex:r.index,frameId:c?.lines[0].frameId??null};
      })}))}};
}
module.exports={localPairBandTop,build,groups,capacity,tableRows};
if(require.main===module){
  const [input,output]=process.argv.slice(2);
  const request=build(JSON.parse(fs.readFileSync(input,'utf8').replace(/^\uFEFF/,'')));
  fs.writeFileSync(output,JSON.stringify(request,null,2)+'\n');
  console.log(JSON.stringify({columns:request.columns.length,deferred:request.deferred}));
}
