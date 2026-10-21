param([Parameter(Mandatory=$true)][string]$ConfigPath,[Parameter(Mandatory=$true)][string]$ReportPath)
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$config=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8|ConvertFrom-Json
$folder=Split-Path -Parent $ReportPath
$fixture=Join-Path $folder 'spacing_table_fixture_QA.indd'
if(Test-Path -LiteralPath $fixture){throw 'Regression fixture already exists'}
Copy-Item -LiteralPath $config.documentPath -Destination $fixture
$config.documentPath=$fixture.Replace('\','/')
$json=$config|ConvertTo-Json -Depth 20 -Compress
$module=[IO.File]::ReadAllText((Join-Path $project '2-导入_InDesign\journal_layout_rules.jsxinc'))
$app=New-Object -ComObject InDesign.Application.2020
$cases=@(
 @{name='top-inset';want='FRAME_TOP_INSET';code='s.textContainers[2].textFramePreferences.insetSpacing=[2,0,0,0];'},
 @{name='bottom-vertical-alignment';want='FRAME_VERTICAL_ALIGNMENT';code='s.textContainers[2].textFramePreferences.verticalJustification=VerticalJustification.BOTTOM_ALIGN;'},
 @{name='artificial-first-baseline';want='FRAME_FIRST_BASELINE_OFFSET';code='s.textContainers[2].textFramePreferences.minimumFirstBaselineOffset=6;'},
 @{name='lower-guide-touching-ink';want='FOOTER_SPACING';code='var a=d.allPageItems;for(var i=0;i<a.length;i++)if(/^spacing-guide/.test(a[i].label)&&a[i].geometricBounds[0]>230){var b=a[i].geometricBounds;b[0]-=.8;b[2]-=.8;a[i].geometricBounds=b;break;}'},
 @{name='table-single-character-tail';want='TABLE_ORPHAN';code='var t=d.stories.itemByID(c.bindings.filter(function(x){return x.role==="tables";})[0].id).tables[0];var cell=t.cells.itemByName("2:1");cell.contents="2号无人机路\n径";'},
 @{name='comparison-not-song';want='COMPARISON_FONT';code='s.paragraphs[1].characters[0].contents=String.fromCharCode(8805);s.paragraphs[1].characters[0].appliedFont=app.fonts.itemByName("黑体");'},
 @{name='formula-actual-font-size';want='FORMULA_ACTUAL_SIZE';code='var a=d.allGraphics;for(var i=0;i<a.length;i++)if(/^source-formula-/.test(a[i].parent.label)){a[i].horizontalScale=85;break;}'},
 @{name='tracking-over-20';want='BODY_TRACKING';code='s.paragraphs[1].tracking=20.1;'}
)
$results=[Collections.Generic.List[string]]::new()
try{
 foreach($case in $cases){
  $script=$module+"`nvar c="+$json+@"
;
(function(){var d=app.open(File(c.documentPath),false);try{JournalLayout.bind(d,c);var s=null;for(var b=0;b<c.bindings.length;b++)if(c.bindings[b].role==='body')s=d.stories.itemByID(c.bindings[b].id);
$($case.code)
d.recompose();var r=JournalLayout.audit(d,c),codes=[];for(var i=0;i<r.errors.length;i++)codes.push(r.errors[i].code);return codes.join(',');}catch(e){return 'ERROR '+e+' LINE '+e.line;}finally{d.close(SaveOptions.NO);}})();
"@
  # ExtendScript ES3 has no Array.filter; use the known table story binding.
  $tableRole=@($config.bindings|Where-Object{$_.role -eq 'tables'})[0].id
  $script=$script.Replace('c.bindings.filter(function(x){return x.role==="tables";})[0].id',[string]$tableRole)
  $got=[string]$app.DoScript($script,1246973031)
  if($got.StartsWith('ERROR') -or @($got -split ',') -notcontains $case.want){throw "Failed $($case.name): $got"}
  $results.Add("PASS $($case.name) detected $($case.want)")
 }
 [IO.File]::WriteAllText($ReportPath,($results -join "`n"),[Text.UTF8Encoding]::new($false))
}finally{Remove-Item -LiteralPath $fixture -Force}
$results