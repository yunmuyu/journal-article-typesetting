param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$outputRoot=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$imagePath=Join-Path $outputRoot 'synthetic.png'
[IO.File]::WriteAllBytes($imagePath,[Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP4z8AARAwQCgAf7gP9i18U1AAAAABJRU5ErkJggg=='))
$root=Join-Path $PSScriptRoot '..\2-导入_InDesign'
Import-Module (Join-Path $root 'JournalInDesignScript.psm1') -Force
$env:JOURNAL_SCRIPT_ENGINE='journal-layout-synthetic-regression'
$prefix=[IO.File]::ReadAllText((Join-Path $root 'journal_regression_snapshot.jsxinc'))
foreach($file in @('journal_layout_rules.jsxinc','journal_article_assembly.jsxinc','journal_reflow.jsxinc')){$prefix+="`n"+[IO.File]::ReadAllText((Join-Path $root $file))}
$reportPath=Join-Path $outputRoot 'native-layout-invariants.json'
$reportJson=ConvertTo-Json $reportPath -Compress
$imageJson=ConvertTo-Json $imagePath -Compress
$code=@"
(function(){var d=null,r={passed:false,saved:false},oldUnit=app.scriptPreferences.measurementUnit,oldUI=app.scriptPreferences.userInteractionLevel;
function check(ok,message){if(!ok)throw Error(message);}
function pt(v){return Number(v)*72/25.4;}
try{
app.scriptPreferences.measurementUnit=MeasurementUnits.MILLIMETERS;app.scriptPreferences.userInteractionLevel=UserInteractionLevels.NEVER_INTERACT;
d=app.documents.add(false);r.documentId=d.id;
var frame=d.pages[0].textFrames.add({geometricBounds:[20,20,250,180]});
frame.contents='MARKER\rSYNTHETIC BODY\r\r\r（a）synthetic caption\rHEADING\rEQUATION\rTABLE CAPTION\r';
var s=frame.parentStory;s.insertLabel('journal-role','body');
var body=d.paragraphStyles.add({name:'正文_wrd_1',firstLineIndent:'22pt',pointSize:10.5,leading:15});
var caption=d.paragraphStyles.add({name:'图注/表名',firstLineIndent:0,pointSize:9,leading:14});
var heading=d.paragraphStyles.add({name:'一级标题',firstLineIndent:0});
var equation=d.paragraphStyles.add({name:'公式',firstLineIndent:0});
s.paragraphs[0].applyParagraphStyle(caption,true);s.paragraphs[1].applyParagraphStyle(body,true);
// Replay the historical whole-paragraph replacement separately from the safe assembly helper.
var p=s.paragraphs[0];p.contents='\r';p.applyParagraphStyle(caption,true);p.firstLineIndent=0;
r.wholeParagraphReplacementNextIndentPt=pt(s.paragraphs[1].firstLineIndent);
// Restore the controlled starting state and exercise the actual shared assembly helper.
s.paragraphs[0].contents='MARKER\r';s.paragraphs[1].applyParagraphStyle(body,true);
JournalArticleAssembly.clearPayload(s.paragraphs[0]);
s.paragraphs[0].applyParagraphStyle(caption,true);s.paragraphs[0].firstLineIndent=0;
check(Math.abs(pt(s.paragraphs[1].firstLineIndent)-22)<.001,'clearPayload must preserve following body indent');
s.paragraphs[1].firstLineIndent=0;
s.paragraphs[2].applyParagraphStyle(caption,true);s.paragraphs[3].applyParagraphStyle(caption,true);s.paragraphs[4].applyParagraphStyle(caption,true);
s.paragraphs[5].applyParagraphStyle(heading,true);s.paragraphs[6].applyParagraphStyle(equation,true);s.paragraphs[7].applyParagraphStyle(caption,true);
var rect=d.pages[0].rectangles.add({geometricBounds:[20,20,30,40]});rect.place(File($imageJson));rect.label='synthetic-external-image';
rect.anchoredObjectSettings.insertAnchoredObject(s.paragraphs[2].insertionPoints[0],AnchorPosition.ABOVE_LINE);
s.paragraphs[3].leading='2pt';d.recompose();
check(JournalLayout.bodyIndentation(d,false).length===1,'detect native local zero override');
check(JournalLayout.inlineCaptionSpacing(d,false).length===1,'detect native subcaption 2pt override');
JournalLayout.bodyIndentation(d,true);JournalLayout.inlineCaptionSpacing(d,true);
JournalLayout.bodyIndentation(d,true);JournalLayout.inlineCaptionSpacing(d,true);
check(Math.abs(pt(s.paragraphs[1].firstLineIndent)-22)<.001,'restore native template indent');
check(Number(s.paragraphs[3].leading)===5,'restore native 5pt gap');
for(var i=5;i<=7;i++)check(Number(s.paragraphs[i].firstLineIndent)===0,'non-body indent changed '+i);
// Real reflow compression changes body leading and frame heights, preserving the fixed gap and indent.
var second=d.pages[0].textFrames.add({geometricBounds:[20,182,250,200]});second.previousTextFrame=frame;
var prose=s.paragraphs[1],start=prose.insertionPoints[0].index,end=prose.insertionPoints[-1].index;
var plan={schemaVersion:1,documentId:d.id,storyId:s.id,tracking:[],leadingCompression:[{start:start,end:end,text:String(prose.contents),leading:14.8}],lastPageBalance:{frameIds:[frame.id,second.id]}};
JournalReflow.apply(d,plan,function(){return [];});
check(JournalLayout.bodyIndentation(d,false).length===0,'reflow changed native body indent');
check(JournalLayout.inlineCaptionSpacing(d,false).length===0,'reflow changed native fixed caption gap');
r.indentPt=pt(s.paragraphs[1].firstLineIndent);r.captionGapPt=Number(s.paragraphs[3].leading);r.compressedLeadingPt=Number(s.paragraphs[1].leading);r.passed=true;
}catch(e){r.error=String(e);r.line=e.line;}finally{if(d)d.close(SaveOptions.NO);app.scriptPreferences.measurementUnit=oldUnit;app.scriptPreferences.userInteractionLevel=oldUI;var f=File($reportJson);f.encoding='UTF-8';f.open('w');f.write(JournalRegressionSnapshot.json(r));f.close();}
}());
"@
$app=New-Object -ComObject InDesign.Application.2020
Invoke-JournalInDesignScript -Application $app -Code ($prefix+"`n"+$code) | Out-Null
$result=Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
if(-not $result.passed){throw ($result | ConvertTo-Json -Compress)}
$result | ConvertTo-Json -Compress
