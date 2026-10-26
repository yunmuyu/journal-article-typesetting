#Requires -Version 7.0
param([Parameter(Mandatory)][string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
$evidence=[IO.Path]::GetFullPath($EvidenceDirectory)
if(Test-Path -LiteralPath $evidence){throw 'NATIVE_GAP_EVIDENCE_ALREADY_EXISTS'}
[void][IO.Directory]::CreateDirectory($evidence)
$tool=Join-Path $PSScriptRoot '../2-导入_InDesign'
Import-Module (Join-Path $tool 'JournalInDesignScript.psm1') -Force
$job=@{folder=$evidence}|ConvertTo-Json -Compress
$code=[IO.File]::ReadAllText((Join-Path $tool 'journal_regression_snapshot.jsxinc'))+"var NativeGapJob=$job;"+@'
(function(job){var d=null,ownedId=null,ui=app.scriptPreferences.userInteractionLevel,result;
 try{
  app.scriptPreferences.userInteractionLevel=UserInteractionLevels.NEVER_INTERACT;
  var fixtures=[];
  for(var variant=0;variant<4;variant++){
   d=app.documents.add(false);ownedId=d.id;d.documentPreferences.properties={facingPages:false,pageWidth:'210mm',pageHeight:'297mm',pagesPerDocument:2};
   d.viewPreferences.horizontalMeasurementUnits=MeasurementUnits.MILLIMETERS;d.viewPreferences.verticalMeasurementUnits=MeasurementUnits.MILLIMETERS;d.viewPreferences.rulerOrigin=RulerOrigin.PAGE_ORIGIN;d.zeroPoint=[0,0];
   var frames=[],page;for(var i=0;i<4;i++){page=d.pages[Math.floor(i/2)];var x=14.5;if(i%2)x+=92.5;frames.push(page.textFrames.add({geometricBounds:[26,x,148,x+85.5]}));if(i)frames[i-1].nextTextFrame=frames[i];}
   var body=frames[0].parentStory;body.insertLabel('journal-role','body');
   var font=app.fonts.itemByName('宋体\tRegular');if(!font.isValid||font.status!==FontStatus.INSTALLED)throw Error('NATIVE_GAP_TEST_FONT_MISSING');
   var leading=16;if(variant>0)leading=14.8;
   var style=d.paragraphStyles.add({name:'正文',appliedFont:font,pointSize:10.5,leading:leading,spaceBefore:0,spaceAfter:0,keepAllLinesTogether:false,keepWithNext:0});
   if(variant===3){
    body.contents='\rTail paragraph.\r';body.paragraphs.everyItem().appliedParagraphStyle=style;
    var table=body.insertionPoints[0].tables.add({bodyRowCount:4,columnCount:2});table.columns.everyItem().width=42.75;
    for(i=0;i<table.cells.length;i++){var cell=table.cells[i];cell.contents='A';cell.topInset=0;cell.bottomInset=0;cell.texts[0].pointSize=9;cell.texts[0].leading=12;}
    table.cells[-1].contents='Two\rLines';table.cells[-1].texts[0].pointSize=9;table.cells[-1].texts[0].leading=12;
    for(i=0;i<table.rows.length;i++){table.rows[i].autoGrow=true;table.rows[i].minimumHeight=5.2;table.rows[i].height=5.2;}
    table.rows[0].rowType=RowTypes.HEADER_ROW;d.recompose();var tablePath=File(job.folder+'/table-source_QA.indd');d.save(tablePath);fixtures.push(tablePath.fsName);d.close(SaveOptions.NO);d=null;continue;
   }
   var text='',prefixCount=14;if(variant===1)prefixCount=16;if(variant===2)prefixCount=20;
   for(i=0;i<prefixCount;i++)text+='Synthetic paragraph '+i+'. Stable text.\r';
   var insertion=text.length;text+='\n(1)\r';for(i=0;i<14;i++)text+='Following paragraph '+i+'. Stable text.\r';
   body.contents=text;body.paragraphs.everyItem().appliedParagraphStyle=style;
   var group=d.rectangles.add({geometricBounds:[0,0,43,70],fillColor:d.swatches.itemByName('None'),strokeColor:d.swatches.itemByName('Black'),strokeWeight:.5});group.label='source-formula-1';
   group.anchoredObjectSettings.insertAnchoredObject(body.insertionPoints[insertion],AnchorPosition.INLINE_POSITION);
   var p=group.parent.paragraphs[0];p.keepAllLinesTogether=true;p.justification=Justification.CENTER_ALIGN;p.leading=44*72/25.4;p.lines[-1].characters.everyItem().leading=15;
   d.recompose();var name='pull-source_QA.indd';if(variant===1)name='blocked-source_QA.indd';if(variant===2)name='push-source_QA.indd';var path=File(job.folder+'/'+name);d.save(path);fixtures.push(path.fsName);d.close(SaveOptions.NO);d=null;
  }
  result={status:'fixtures-created',files:fixtures};
 }catch(e){result={status:'failed',error:String(e),line:e.line};}
 finally{if(d&&d.isValid&&d.id===ownedId)d.close(SaveOptions.NO);app.scriptPreferences.userInteractionLevel=ui;}
 return JournalRegressionSnapshot.json(result);
})(NativeGapJob);
'@
$priorEngine=$env:JOURNAL_SCRIPT_ENGINE
try{
 $env:JOURNAL_SCRIPT_ENGINE='journal-gap-native-test-v5'
 [IO.File]::WriteAllText((Join-Path $evidence 'create-fixtures.jsx'),$code)
 $app=New-Object -ComObject InDesign.Application.2020
 $native=([string](Invoke-JournalInDesignScript -Application $app -Code $code))|ConvertFrom-Json
 if($native.status -ne 'fixtures-created'){throw ($native|ConvertTo-Json -Compress)}
 $config=@{gapSolver=@{maxBlankMm=12;maxWindowFrames=4;maxCandidates=6;maxBoundaries=1;maxMilliseconds=30000}}|ConvertTo-Json -Depth 5
 $configPath=Join-Path $evidence 'config.json';[IO.File]::WriteAllText($configPath,$config)
 & (Join-Path $tool 'Invoke-JournalGapLayout.ps1') -SourcePath (Join-Path $evidence 'pull-source_QA.indd') -OutputPath (Join-Path $evidence 'pull-result_QA.indd') -ReportPath (Join-Path $evidence 'pull-result.json') -ConfigPath $configPath
 try{& (Join-Path $tool 'Invoke-JournalGapLayout.ps1') -SourcePath (Join-Path $evidence 'blocked-source_QA.indd') -OutputPath (Join-Path $evidence 'blocked-result_QA.indd') -ReportPath (Join-Path $evidence 'blocked-result.json') -ConfigPath $configPath;throw 'NATIVE_GAP_BLOCKED_DID_NOT_STOP'}catch{if([string]$_ -notmatch 'GAP_UNRESOLVED'){throw}}
 & (Join-Path $tool 'Invoke-JournalGapLayout.ps1') -SourcePath (Join-Path $evidence 'push-source_QA.indd') -OutputPath (Join-Path $evidence 'push-result_QA.indd') -ReportPath (Join-Path $evidence 'push-result.json') -ConfigPath $configPath
 $pull=Get-Content -Raw (Join-Path $evidence 'pull-result.json')|ConvertFrom-Json
 $blocked=Get-Content -Raw (Join-Path $evidence 'blocked-result.json')|ConvertFrom-Json
 $push=Get-Content -Raw (Join-Path $evidence 'push-result.json')|ConvertFrom-Json
 if($pull.appliedDecisions -lt 1 -or $pull.decisions[0].selected.mode -ne 'pull'){throw 'NATIVE_GAP_PULL_NOT_PROVEN'}
 if($pull.pages -ne 2 -or $pull.articlePageRange[1] -ne 1){throw 'NATIVE_GAP_TAIL_PAGES_CHANGED'}
 if($blocked.status -ne 'blocked-large-gaps' -or $blocked.appliedDecisions -ne 0){throw 'NATIVE_GAP_BLOCKED_NOT_PROVEN'}
 if($push.appliedDecisions -lt 1 -or $push.decisions[0].selected.mode -ne 'push'){throw 'NATIVE_GAP_PUSH_NOT_PROVEN'}
 if(-not $pull.sourceFileUnchanged -or -not $blocked.sourceFileUnchanged -or -not $push.sourceFileUnchanged){throw 'NATIVE_GAP_SOURCE_CHANGED'}
 $rowCode=''
 foreach($module in @('journal_document_session.jsxinc','journal_regression_snapshot.jsxinc','journal_layout_measurement.jsxinc','journal_gap_solver.jsxinc','journal_gap_layout.jsxinc')){$rowCode+=[IO.File]::ReadAllText((Join-Path $tool $module))+"`n"}
 $rowJob=@{path=(Join-Path $evidence 'table-source_QA.indd')}|ConvertTo-Json -Compress
 $rowCode+="var RowGapJob=$rowJob;"+@'
(function(job){var session=null,d=null,result;
 try{
  session=JournalDocumentSession.acquire(app,job.path);d=session.document;if(!session.openedHere)throw Error('ROW_TEST_ALREADY_OPEN');
  var a=JournalGapLayout.adapter(d,{}),state=a.measure(),ops=[];
  for(var i=0;i<state.columns.length;i++)for(var j=0;j<state.columns[i].adjustments.length;j++){var op=state.columns[i].adjustments[j];if(op.kind==='row')ops.push(op);}
  if(ops.length!==2||ops[0].target.row!==1||ops[1].target.row!==2)throw Error('ROW_TEST_ELIGIBILITY '+ops.length);
  var saved=a.snapshot(state),op=ops[0];a.apply({operations:[{kind:'row',target:op.target,from:op.from,to:4.8,min:4.8,max:5.5}]});
  var body=d.stories[0];for(i=0;i<d.stories.length;i++)if(d.stories[i].extractLabel('journal-role')==='body')body=d.stories[i];
  if(Math.abs(body.tables[0].rows[1].height-4.8)>.02)throw Error('ROW_TEST_HEIGHT_NOT_CHANGED');
  a.restore(saved);if(Math.abs(body.tables[0].rows[1].height-5.2)>.02)throw Error('ROW_TEST_HEIGHT_NOT_RESTORED');
  result={status:'row-budget-passed',eligibleRows:ops.length,minimumMm:4.8,restoredMm:5.2};
 }catch(e){result={status:'failed',error:String(e),line:e.line};}
 finally{if(session&&session.openedHere)JournalDocumentSession.close(d||session.document,session,SaveOptions.NO);}
 return JournalRegressionSnapshot.json(result);
})(RowGapJob);
'@
 $rowBefore=(Get-FileHash -LiteralPath (Join-Path $evidence 'table-source_QA.indd')).Hash
 $rowResult=([string](Invoke-JournalInDesignScript -Application $app -Code $rowCode))|ConvertFrom-Json
 [IO.File]::WriteAllText((Join-Path $evidence 'table-result.json'),($rowResult|ConvertTo-Json))
 if($rowResult.status -ne 'row-budget-passed' -or (Get-FileHash -LiteralPath (Join-Path $evidence 'table-source_QA.indd')).Hash -ne $rowBefore){throw ('NATIVE_GAP_ROW_NOT_PROVEN '+($rowResult|ConvertTo-Json -Compress))}
 'PASS native pull, push and budget-exhausted cases; unresolved gaps stop the caller; originals unchanged'
 'PASS native table-row budget and exact rollback; header and multiline rows excluded'
}finally{$env:JOURNAL_SCRIPT_ENGINE=$priorEngine}
