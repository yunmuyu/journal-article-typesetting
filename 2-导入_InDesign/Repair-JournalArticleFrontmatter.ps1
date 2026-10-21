param(
 [Parameter(Mandatory=$true)][string]$ConfigPath,
 [Parameter(Mandatory=$true)][string]$OutputDirectory,
 [Parameter(Mandatory=$true)][string]$MasterTemplatePath
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'JournalInDesignScript.psm1') -Force
$job=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8|ConvertFrom-Json
$audit=Get-Content -LiteralPath $job.auditConfigPath -Raw -Encoding UTF8|ConvertFrom-Json
$directory=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $directory){throw 'FRONTMATTER_OUTPUT_EXISTS'}
if([IO.Path]::GetFileName($directory) -notmatch '(?i)QA|copy|副本'){throw 'FRONTMATTER_QA_DIRECTORY_REQUIRED'}
[void][IO.Directory]::CreateDirectory($directory)
$target=Join-Path $directory ([IO.Path]::GetFileNameWithoutExtension($job.outputPath)+'_篇首修订_QA.indd')
Copy-Item -LiteralPath $job.outputPath -Destination $target
$supp=Get-Content -LiteralPath $job.supplementPath -Raw -Encoding UTF8|ConvertFrom-Json
$front=@();foreach($role in @('cnTitle','cnAuthor','cnAffiliation','cnAbstract','cnKeywords','classification','enTitle','enAuthor','enAffiliation','enAbstract','enKeywords')){$value=$supp.front[$job.frontmatter.indices.$role];$front+=@{role=$role;text=$value.text;runs=@($value.runs)}}
$footer=@(@{role='received';text=$supp.received});$fund=$supp.front[$job.frontmatter.indices.fund];if($fund -and $fund.text.Trim()){$footer+=@{role='fund';text=$fund.text}}
$job.frontmatter.contract|Add-Member -NotePropertyName preserveExistingParagraphs -NotePropertyValue $true -Force
$spec=@{path=$target;master=[IO.Path]::GetFullPath($MasterTemplatePath);data=@{front=$front;footer=$footer};contract=$job.frontmatter.contract}|ConvertTo-Json -Depth 70 -Compress
$code=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_frontmatter.jsxinc'))+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_regression_snapshot.jsxinc'))+@"
(function(s){var d=null,source=null,oldUI=app.scriptPreferences.userInteractionLevel;try{
 app.scriptPreferences.userInteractionLevel=UserInteractionLevels.NEVER_INTERACT;
 d=app.open(File(s.path),false).getElements()[0];source=app.open(File(s.master),false).getElements()[0];
 function slot(name){var items=d.allPageItems;for(var i=0;i<items.length;i++)if((','+items[i].extractLabel('journal-slot-aliases')+',').indexOf(','+name+',')>=0)return items[i];throw Error('FRONT_SLOT '+name);}
 function label(name){var items=d.allPageItems;for(var i=0;i<items.length;i++)if(items[i].label===name)return items[i];throw Error('FRONT_LABEL '+name);}
 var front=slot('front-title'),before=front.paragraphs[3].lines[0].baseline-front.paragraphs[2].lines[-1].baseline;
 JournalFrontmatter.apply(d,{front:front,footer:slot('received-fund'),bodyColumns:[slot('body-left'),slot('body-right')],topGray:label('spacing-guide-top'),bottomGray:label('spacing-guide-footer'),separator:label('article-footer-separator')},s.data,s.contract);
 var after=front.paragraphs[3].lines[0].baseline-front.paragraphs[2].lines[-1].baseline;if(Math.abs(before-after)>.02)throw Error('UNIT_TO_ABSTRACT_GAP_CHANGED '+before+' => '+after);
 var restored=0,expected=[],targetOrigin=d.viewPreferences.rulerOrigin;source.viewPreferences.rulerOrigin=RulerOrigin.SPREAD_ORIGIN;d.viewPreferences.rulerOrigin=RulerOrigin.SPREAD_ORIGIN;
 for(var mi=0;mi<source.masterSpreads.length;mi++){var sm=source.masterSpreads[mi],tm=d.masterSpreads.itemByName(sm.name);if(!tm.isValid)continue;
  for(var pi=0;pi<sm.pages.length;pi++){var items=sm.pages[pi].allPageItems;
   for(var i=0;i<items.length;i++){var sf=items[i];if(sf.constructor.name!=='TextFrame'||sf.label!=='journal-restored-right-footer-date')continue;
    var found=false,existing=tm.pages[pi].allPageItems;for(var ei=0;ei<existing.length;ei++)if(existing[ei].constructor.name==='TextFrame'&&/^\d{4}\.\d{2}$/.test(String(existing[ei].contents)))found=true;
    if(!found){var b=sf.geometricBounds,sp=sm.pages[pi].bounds,tp=tm.pages[pi].bounds,copy=sf.duplicate(tm.pages[pi]).getElements()[0];copy.geometricBounds=[b[0]-sp[0]+tp[0],b[1]-sp[1]+tp[1],b[2]-sp[0]+tp[0],b[3]-sp[1]+tp[1]];restored++;}
   }
  }
 }
 d.viewPreferences.rulerOrigin=targetOrigin;
 for(mi=0;mi<d.masterSpreads.length;mi++){var m=d.masterSpreads[mi];for(pi=0;pi<m.pages.length;pi++){items=m.pages[pi].allPageItems;for(i=0;i<items.length;i++)if(items[i].constructor.name==='TextFrame'&&String(items[i].contents).length)expected.push({masterName:m.name,pageIndex:pi,bounds:items[i].geometricBounds,text:String(items[i].contents)});}}
 d.save();return JournalRegressionSnapshot.json({status:'frontmatter-corrected-unchecked',restoredRightDates:restored,abstractGapBeforeMm:before,abstractGapAfterMm:after,masterTextExpectations:expected});
 }catch(e){return JournalRegressionSnapshot.json({status:'failed',failure:String(e),line:e.line});}finally{if(d&&d.isValid)d.close(SaveOptions.NO);if(source&&source.isValid)source.close(SaveOptions.NO);app.scriptPreferences.userInteractionLevel=oldUI;}})($spec);
"@
$app=New-Object -ComObject InDesign.Application.2020
$result=([string](Invoke-JournalInDesignScript -Application $app -Code $code))|ConvertFrom-Json
if($result.status -ne 'frontmatter-corrected-unchecked'){throw ('FRONTMATTER_REPAIR_FAILED '+($result|ConvertTo-Json -Compress))}
$audit.documentPath=$target;$audit.auditPath=Join-Path $directory '修订.audit.xml'
$audit|Add-Member -NotePropertyName masterTextExpectations -NotePropertyValue $result.masterTextExpectations -Force
$audit|Add-Member -NotePropertyName requireMasterTextContract -NotePropertyValue $true -Force
$auditPath=Join-Path $directory '检查配置.json'
[IO.File]::WriteAllText($auditPath,($audit|ConvertTo-Json -Depth 80),[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $directory '篇首修订结果.json'),($result|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
$auditPath
