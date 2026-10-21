$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$modulePath=Join-Path $project '2-导入_InDesign\journal_bottom_plan.jsxinc'
$rulesPath=Join-Path $project '2-导入_InDesign\journal_layout_rules.jsxinc'
$entryPath=Join-Path $project '2-导入_InDesign\Invoke-JournalLayout.ps1'
function Assert-True([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$module=[IO.File]::ReadAllText($modulePath,[Text.Encoding]::UTF8)
$rules=[IO.File]::ReadAllText($rulesPath,[Text.Encoding]::UTF8)
$entry=[IO.File]::ReadAllText($entryPath,[Text.Encoding]::UTF8)
Assert-True ($entry.Contains('journal_bottom_plan.jsxinc')) 'entry must load the bottom-plan module'
Assert-True ($entry.Contains('bottomPlanPath')) 'entry must resolve a bottom-plan path'
Assert-True ($entry.IndexOf('$embeddedBottomPlan.Value -isnot [string]',[StringComparison]::Ordinal) -lt $entry.IndexOf('$bottomPlanPathProperty.Value',[StringComparison]::Ordinal)) 'embedded plan object must take precedence over a path'
Assert-True ($entry.IndexOf('BOTTOM_TARGET_MISSING',[StringComparison]::Ordinal) -lt $entry.IndexOf("New-Object -ComObject 'InDesign.Application.2020'",[StringComparison]::Ordinal)) 'missing targets must block before COM'
Assert-True ($rules.Contains('JournalBottomPlan.apply(d,c.bottomPlan)')) 'JournalLayout must apply the supplied plan'
Assert-True ($rules -match 'if\(c\.bottomPlan\)\{(?<plan>[^}]+)\}else\{(?<fallback>[^}]+)\}') 'bottom plan and iterative fallback must remain separate branches'
Assert-True ($Matches.plan.Contains('JournalBottomPlan.apply(d,c.bottomPlan)') -and -not $Matches.plan.Contains('alignBottom(') -and $Matches.fallback.Contains('alignBottom(d)')) 'bottom plan must bypass iterative alignBottom'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('journal-bottom-apply-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp)|Out-Null
try{
$testPath=Join-Path $temp 'test.js'
$blockedPath=Join-Path $temp 'blocked-plan.json'
$configPath=Join-Path $temp 'config.json'
[IO.File]::WriteAllText($blockedPath,(@{status='blocked';blankSpaceAllowed=$false;columns=@()}|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
$config=[ordered]@{configVersion='bottom-plan-regression-v1';templateContractVersion='qa-template-contract-v2';documentPath=(Join-Path $temp 'missing-QA.indd');auditPath=(Join-Path $temp 'audit.xml');bottomPlanPath='blocked-plan.json'}
[IO.File]::WriteAllText($configPath,($config|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
$pathBlocked=$false
try{& $entryPath -ConfigPath $configPath -Mode Apply}catch{$pathBlocked=$_.Exception.Message -match 'BOTTOM_PLAN_STATUS blocked'}
Assert-True $pathBlocked 'relative bottomPlanPath must resolve and block before COM'
$config.Remove('bottomPlanPath');$config.bottomPlan='blocked-plan.json'
[IO.File]::WriteAllText($configPath,($config|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
$stringPathBlocked=$false
try{& $entryPath -ConfigPath $configPath -Mode Apply}catch{$stringPathBlocked=$_.Exception.Message -match 'BOTTOM_PLAN_STATUS blocked'}
Assert-True $stringPathBlocked 'bottomPlan string path must resolve before COM'
$config.bottomPlan=[ordered]@{status='ready';blankSpaceAllowed=$false;columns=@([ordered]@{adjustments=@([ordered]@{kind='leading';id='missing-target';role='body';toPt=15})})}
[IO.File]::WriteAllText($configPath,($config|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
$objectWon=$false
try{& $entryPath -ConfigPath $configPath -Mode Apply}catch{$objectWon=$_.Exception.Message -match 'BOTTOM_TARGET_MISSING missing-target'}
Assert-True $objectWon 'embedded bottomPlan object must take precedence and block before COM'
$script=$module+@"
const assert=require('assert');
global.CoordinateSpaces={PASTEBOARD_COORDINATES:'pasteboard'};
global.AnchorPoint={CENTER_ANCHOR:'center'};
global.ResizeMethods={MULTIPLYING_CURRENT_DIMENSIONS_BY:'multiply'};
function range(){return {leading:15,tracking:0};}
const textRange=range();
const story={extractLabel:function(){return 'body';},characters:{itemByRange:function(start,end){assert.equal(start,10);assert.equal(end,30);return textRange;}},tables:[]};
const row={minimumHeight:5};
const table={label:'source-table-1',rows:[row]}; story.tables.push(table);
const figure={label:'source-figure-3',resizeCalls:[],resize:function(space,anchor,method,scale){this.resizeCalls.push({space,anchor,method,scale});}};
const doc={stories:[story],allPageItems:[figure],recomposeCount:0,recompose:function(){this.recomposeCount++;}};
const plan={status:'ready',blankSpaceAllowed:false,columns:[{adjustments:[
 {kind:'leading',id:'body-lines',role:'body',toPt:15.2,target:{storyRole:'body',startIndex:10,endIndex:30}},
 {kind:'tracking',id:'paragraph-7',to:8.5,orphanFree:true,target:{storyRole:'body',startIndex:10,endIndex:30}},
 {kind:'figure-height',id:'figure-3',fromScalePct:100,toScalePct:102,target:{label:'source-figure-3'}},
 {kind:'table-row-height',id:'table-1-row-1',toMm:5.4,target:{tableLabel:'source-table-1',rowIndex:0}}
]}]};
const result=JournalBottomPlan.apply(doc,plan);
assert.equal(result.applied,4);assert.equal(textRange.leading,15.2);assert.equal(textRange.tracking,8.5);assert.equal(row.minimumHeight,5.4);
assert.equal(figure.resizeCalls.length,1);assert.deepEqual(figure.resizeCalls[0].scale,[1.02,1.02]);assert.equal(doc.recomposeCount,1);
const blocked={status:'blocked',blankSpaceAllowed:false,columns:[]};
assert.throws(()=>JournalBottomPlan.apply(doc,blocked),/BOTTOM_PLAN_STATUS/);assert.equal(doc.recomposeCount,1);
const forbidden={status:'ready',blankSpaceAllowed:false,columns:[{adjustments:[{kind:'blank-space',id:'x'}]}]};
assert.throws(()=>JournalBottomPlan.apply(doc,forbidden),/BOTTOM_PLAN_ADJUSTMENT/);assert.equal(doc.recomposeCount,1);
const atomic={status:'ready',blankSpaceAllowed:false,columns:[{adjustments:[plan.columns[0].adjustments[0],{kind:'tracking',id:'bad',to:21,orphanFree:true,target:{storyRole:'body',startIndex:10,endIndex:30}}]}]};
textRange.leading=15;
assert.throws(()=>JournalBottomPlan.apply(doc,atomic),/BOTTOM_TRACKING_RANGE/);assert.equal(textRange.leading,15);assert.equal(doc.recomposeCount,1);
console.log('PASS fake bottom-plan apply is atomic and recomposes once');
"@
[IO.File]::WriteAllText($testPath,$script,[Text.UTF8Encoding]::new($false))
$output=& node $testPath 2>&1
if($LASTEXITCODE -ne 0){throw ($output -join "`n")}
Assert-True (($output -join "`n") -match 'PASS fake bottom-plan') 'fake-object regression did not finish'
}
finally{Remove-Item -LiteralPath $temp -Recurse -Force}
'PASS bottom-plan transaction integration and no-blank guard'
