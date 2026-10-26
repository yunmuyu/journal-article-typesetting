param([Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$folder=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $folder|Out-Null
$root=Join-Path $PSScriptRoot '../2-导入_InDesign'
Import-Module (Join-Path $root 'JournalInDesignScript.psm1') -Force
$code=[IO.File]::ReadAllText((Join-Path $root 'journal_regression_snapshot.jsxinc'))+[IO.File]::ReadAllText((Join-Path $root 'journal_layout_rules.jsxinc'))
$code+=@'
(function(){var d=null,old=app.scriptPreferences.measurementUnit,r={passed:false,saved:false};
function check(ok,msg){if(!ok)throw Error(msg);}
try{
app.scriptPreferences.measurementUnit=MeasurementUnits.MILLIMETERS;
d=app.documents.add(false);d.viewPreferences.horizontalMeasurementUnits=MeasurementUnits.MILLIMETERS;d.viewPreferences.verticalMeasurementUnits=MeasurementUnits.MILLIMETERS;
var f=d.pages[0].textFrames.add({geometricBounds:[20,20,150,160]}),t=f.insertionPoints[0].tables.add({bodyRowCount:4,columnCount:2});t.label='source-table-1';
t.cells.everyItem().contents='A';t.cells.everyItem().texts[0].pointSize='9pt';t.cells.everyItem().texts[0].leading='12pt';
t.columns.everyItem().width=30;t.rows.everyItem().minimumHeight=4.7;t.rows.everyItem().autoGrow=true;t.rows[0].rowType=RowTypes.HEADER_ROW;
t.cells[2].contents='X1';t.cells[2].texts[0].characters[1].position=Position.SUPERSCRIPT;t.cells[3].contents='12';t.cells[3].texts[0].justification=Justification.RIGHT_ALIGN;
var config={tableKinds:[{kind:'ordinary'}]};JournalLayout.normalizeOrdinaryTables([t],config);t.rows.everyItem().height=4.7;d.recompose();
check(t.headerRowCount===1,'header lost');check(t.cells[2].texts[0].characters[1].position===Position.SUPERSCRIPT,'superscript lost');
check(t.cells[3].texts[0].justification===Justification.RIGHT_ALIGN,'right alignment lost');
check(Math.abs(t.rows[1].minimumHeight-4.7)<.02,'approved minimum lost');
r.nativeIssues=JournalLayout.tableNativeIssues(t);r.height=t.rows[1].height;check(r.nativeIssues.length===0,'restored native format failed');
t.cells[2].leftInset=1;check(JournalLayout.tableNativeIssues(t).length>0,'bad inset accepted');JournalLayout.normalizeOrdinaryTables([t],config);
var before=t.cells[2].leftInset;try{JournalLayout.normalizeOrdinaryTables([t],{tableKinds:[{kind:'unclassified'}]});throw Error('unclassified accepted');}catch(e){check(String(e).indexOf('TABLE_KIND_REQUIRED')>=0,'wrong gate');}
check(t.cells[2].leftInset===before,'gate mutated table');
t.cells[2].contents='1.2';t.cells[4].contents='12';d.recompose();
var issues=JournalLayout.tableNativeIssues(t),mixed=false;for(var i=0;i<issues.length;i++)if(issues[i].code==='TABLE_DECIMAL_INTEGER_REVIEW')mixed=true;
check(mixed,'mixed decimal review missing');r.passed=true;r.minimumMm=t.rows[1].minimumHeight;r.headerRows=t.headerRowCount;r.mixedDecimalBlocked=mixed;
}catch(e){r.error=String(e);r.line=e.line;}finally{if(d&&d.isValid)d.close(SaveOptions.NO);app.scriptPreferences.measurementUnit=old;}
return JournalRegressionSnapshot.json(r);}());
'@
[IO.File]::WriteAllText((Join-Path $folder 'executed.jsx'),$code)
$app=New-Object -ComObject InDesign.Application.2020
$result=([string](Invoke-JournalInDesignScript -Application $app -Code $code))|ConvertFrom-Json
$result|ConvertTo-Json|Set-Content (Join-Path $folder 'native-table-contract.json') -Encoding utf8
if(!$result.passed){throw ($result|ConvertTo-Json -Compress)}
$result|ConvertTo-Json -Compress
