param([Parameter(Mandatory=$true)][string]$ConfigPath,[Parameter(Mandatory=$true)][string]$ReportPath)
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$module=[IO.File]::ReadAllText((Join-Path $project '2-导入_InDesign\journal_layout_rules.jsxinc'))
$cfg=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8|ConvertFrom-Json
$originalConfig=(Get-Item -LiteralPath $ConfigPath).FullName
$originalDocument=$cfg.documentPath
$fixture=Join-Path ([IO.Path]::GetDirectoryName($ReportPath)) 'negative_fixture_QA.indd'
Copy-Item -LiteralPath $cfg.documentPath -Destination $fixture -Force
$cfg.documentPath=$fixture.Replace('\','/')
$cfg.auditPath=(Join-Path ([IO.Path]::GetDirectoryName($ReportPath)) 'negative_audit.xml').Replace('\','/')
$fixtureConfig=Join-Path ([IO.Path]::GetDirectoryName($ReportPath)) 'negative_fixture.json'
[IO.File]::WriteAllText($fixtureConfig,($cfg|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
$json=$cfg|ConvertTo-Json -Depth 20 -Compress
$app=New-Object -ComObject 'InDesign.Application.2020'
$cases=@(
 @{name='wrong-body-font';want='FONT_ROLE';code='s.paragraphs[1].characters[0].appliedFont=app.fonts.itemByName("黑体");'},
 @{name='leading-outside-range';want='BODY_LEADING';code='s.paragraphs[1].leading=17;'},
 @{name='caption-gap';want='CAPTION_GAP';code='for(var i=1;i<s.paragraphs.length;i++)if(/^图\d+\s/.test(String(s.paragraphs[i].contents))){s.paragraphs[i-1].leading=6;break;}'},
 @{name='guide-height';want='GUIDE_HEIGHT';code='var a=d.allPageItems;for(var i=0;i<a.length;i++)if(/^spacing-guide/.test(a[i].label)){var b=a[i].geometricBounds;b[2]+=1;a[i].geometricBounds=b;break;}'},
 @{name='printing-guide';want='GUIDE_PRINTING';code='var a=d.allPageItems;for(var i=0;i<a.length;i++)if(/^spacing-guide/.test(a[i].label)){a[i].nonprinting=false;break;}'},
 @{name='different-page-bottom';want='BOTTOM';code='var f=s.textContainers[2];f.paragraphs[0].leading=14.8;'},
 @{name='missing-table-header';want='TABLE_HEADER';code='s.tables[0].rows[0].rowType=RowTypes.BODY_ROW;'},
 @{name='right-page-start';want='START_SIDE';code='d.sections[0].pageNumberStart=Number(d.sections[0].pageNumberStart)+1;'},
 @{name='figure-not-centered';want='FIGURE_CENTER';code='var a=d.allPageItems;for(var i=0;i<a.length;i++)if(a[i].label==="source-figure-1"){a[i].anchoredObjectSettings.horizontalAlignment=HorizontalAlignment.LEFT_ALIGN;break;}'},
 @{name='figure-inside-conclusion';want='FIGURE_IN_CONCLUSION';code='s.insertionPoints[-1].contents="\r图99  错误位置测试\r";'},
 @{name='composite-font-mapping';want='COMPOSITE_FONT';code='d.compositeFonts.itemByName("现 宋体-1").compositeFontEntries.itemByName("数字").appliedFont="黑体";'}
)
$rows=[Collections.Generic.List[string]]::new()
foreach($case in $cases){
 $script=$module+"`nvar c="+$json+@"
;
var target=File(c.documentPath),wanted=String(target.fsName).toLowerCase(),d=app.open(target),targetId=d.id;
function closeExact(){if(!d||!d.isValid)throw Error('TARGET_DOCUMENT_INVALID');var actual=String(d.fullName.fsName).toLowerCase();if(actual!==wanted)throw Error('TARGET_PATH_CHANGED');if(d.id!==targetId)throw Error('TARGET_ID_CHANGED');d.close(SaveOptions.NO);}
JournalLayout.bind(d,c,false);
var s=d.stories.itemByID(c.bindings[0].id),changed=false,answer='';
try{
 answer=app.doScript(function(){
  $($case.code)
  d.recompose();var r=JournalLayout.audit(d,c),codes=[];for(var i=0;i<r.errors.length;i++)codes.push(r.errors[i].code);return codes.join(',');
 },ScriptLanguage.JAVASCRIPT,[],UndoModes.ENTIRE_SCRIPT,'Journal negative regression');changed=true;
}catch(e){answer='ERROR '+e+' LINE '+e.line;changed=true;}
finally{closeExact();}
answer;
"@
 $got=[string]$app.DoScript($script,1246973031)
 if($got.StartsWith('ERROR') -or @($got -split ',') -notcontains $case.want){throw "Negative regression failed $($case.name): $got"}
 $rows.Add("PASS $($case.name) detected $($case.want)")
}
# Source-content comparison must also reject a missing character, not only overset.
$fixturePathJson=ConvertTo-Json -InputObject $cfg.documentPath -Compress
$mutation='var target=File('+$fixturePathJson+'),wanted=String(target.fsName).toLowerCase(),d=app.open(target),targetId=d.id;if(String(d.fullName.fsName).toLowerCase()!==wanted)throw Error("TARGET_PATH_CHANGED");app.doScript(function(){d.stories.itemByID('+$cfg.bindings[0].id+').paragraphs[1].characters[0].remove();},ScriptLanguage.JAVASCRIPT,[],UndoModes.ENTIRE_SCRIPT,"Missing source text regression");String(targetId);'
$fixtureDocumentId=[int]$app.DoScript($mutation,1246973031)
try{
 $failed=$false
 try{& (Join-Path $project '2-导入_InDesign\Invoke-JournalLayout.ps1') -ConfigPath $fixtureConfig -Mode Check|Out-Null}catch{$failed=$true}
 if(-not $failed){throw 'Missing content was accepted'}
 $report=Get-Content -LiteralPath ([IO.Path]::ChangeExtension($cfg.auditPath,'.result.json')) -Raw -Encoding UTF8|ConvertFrom-Json
 if(-not @($report.errors|Where-Object{$_ -like 'CONTENT paragraph*'}).Count){throw 'CONTENT error missing'}
 $rows.Add('PASS missing-source-character detected CONTENT')
}finally{
 $closeScript='(function(){var wanted=String(File('+$fixturePathJson+').fsName).toLowerCase(),expectedId='+$fixtureDocumentId+',matches=[];for(var i=0;i<app.documents.length;i++){var candidate=app.documents[i];try{if(String(candidate.fullName.fsName).toLowerCase()===wanted)matches.push(candidate);}catch(ignore){}}if(matches.length!==1)throw Error("TARGET_DOCUMENT_COUNT "+matches.length);var d=matches[0];if(d.id!==expectedId)throw Error("TARGET_ID_CHANGED");d.close(SaveOptions.NO);return "RESTORED";})();'
 $app.DoScript($closeScript,1246973031)|Out-Null
}
& (Join-Path $project '2-导入_InDesign\Invoke-JournalLayout.ps1') -ConfigPath $originalConfig -Mode Check|Out-Null
Remove-Item -LiteralPath $fixture,$fixtureConfig -Force
[IO.File]::WriteAllText($ReportPath,($rows -join "`n"),[Text.UTF8Encoding]::new($false))
$rows
