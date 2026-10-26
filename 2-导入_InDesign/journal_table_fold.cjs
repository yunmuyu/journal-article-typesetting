// A planning candidate, not permission to mutate a source table.
// Automatic assembly requires source-cell projection and native fit verification.
function candidate(rows, {columnsPerBlock, columnWidthMm=85.5, merged=false}={}) {
 if(merged)return {status:'ineligible',reason:'merged-cells-require-explicit-mapping'};
 if(rows.length!==2||rows[0].length!==rows[1].length||rows[0].length<3)return {status:'ineligible',reason:'requires-two-rectangular-rows'};
 if(!Number.isInteger(columnsPerBlock)||columnsPerBlock<1)throw Error('FOLD_COLUMNS_REQUIRED');
 const columns=rows[0].length,output=[],sourceCells=[];
 for(let start=1;start<columns;start+=columnsPerBlock){
  for(let row=0;row<2;row++){
   const values=[rows[row][0]],map=[{row,column:0,repeatedLabel:start>1}];
   for(let offset=0;offset<columnsPerBlock;offset++){
    const column=start+offset;values.push(column<columns?rows[row][column]:'');map.push(column<columns?{row,column}:null);
   }
   output.push(values);sourceCells.push(map);
  }
 }
 return {status:'candidate-requires-native-fit',rows:output,sourceCells,columnWidthMm,fontSizePt:9,leadingPt:12,
  require:{noCellOverflow:true,noTrackingCompression:true,sourceDataAndFormattingProjection:true},automaticAssemblyApproved:false};
}
module.exports={candidate};
