param(


    [Parameter(Mandatory=$true)][string]$ConfigPath,


    [ValidateSet('Apply','Check')][string]$Mode='Check',


    [switch]$ExportPreview,


    [ValidateSet('None','Key','Full')][string]$PreviewScope='None',


    [switch]$ExportIdml,


    [switch]$CloseWhenDone,

    [switch]$AllowValidationFailure


)


Import-Module (Join-Path $PSScriptRoot 'JournalInDesignScript.psm1') -Force
$ErrorActionPreference='Stop'


$configFile=(Get-Item -LiteralPath $ConfigPath).FullName


$config=Get-Content -LiteralPath $configFile -Raw -Encoding UTF8|ConvertFrom-Json


if($config.sourceLogicalArticle){$logical=Get-Content -LiteralPath $config.sourceLogicalArticle -Raw -Encoding UTF8|ConvertFrom-Json;$config|Add-Member -NotePropertyName sourceTextFormatting -NotePropertyValue @($logical.blocks) -Force}


if(-not $config.configVersion){throw 'CONFIG_VERSION_MISSING'}


if(-not $config.templateContractVersion){throw 'TEMPLATE_CONTRACT_VERSION_MISSING'}


$embeddedBottomPlan=$config.PSObject.Properties['bottomPlan']


$bottomPlanPathProperty=$config.PSObject.Properties['bottomPlanPath']


$bottomPlan=$null


if($embeddedBottomPlan -and $null -ne $embeddedBottomPlan.Value -and $embeddedBottomPlan.Value -isnot [string]){$bottomPlan=$embeddedBottomPlan.Value}


else{


 $candidatePath=if($bottomPlanPathProperty -and $bottomPlanPathProperty.Value){[string]$bottomPlanPathProperty.Value}elseif($embeddedBottomPlan -and $embeddedBottomPlan.Value -is [string]){[string]$embeddedBottomPlan.Value}else{$null}


 if($candidatePath){if(-not[IO.Path]::IsPathRooted($candidatePath)){$candidatePath=Join-Path ([IO.Path]::GetDirectoryName($configFile)) $candidatePath};$bottomPlan=Get-Content -LiteralPath $candidatePath -Raw -Encoding UTF8|ConvertFrom-Json}


}


if($bottomPlan){


 if($Mode -eq 'Apply'){


  if($bottomPlan.status -ne 'ready'){throw "BOTTOM_PLAN_STATUS $($bottomPlan.status)"}


  if($bottomPlan.blankSpaceAllowed -ne $false){throw 'BOTTOM_PLAN_BLANK_SPACE'}


  foreach($column in @($bottomPlan.columns)){foreach($adjustment in @($column.adjustments)){if($adjustment.kind -notin @('leading','tracking','figure-height','table-row-height')){throw "BOTTOM_PLAN_ADJUSTMENT $($adjustment.kind)"};if($null -eq $adjustment.target){throw "BOTTOM_TARGET_MISSING $($adjustment.id)"}}}


 }


 $config|Add-Member -NotePropertyName bottomPlan -NotePropertyValue $bottomPlan -Force


}


if(-not(Test-Path -LiteralPath $config.documentPath)){throw 'Document does not exist'}


if([IO.Path]::GetFileName($config.documentPath) -notmatch '(QA|copy|副本)'){throw 'Only test copies are allowed'}


$modulePath=Join-Path $PSScriptRoot 'journal_layout_rules.jsxinc'


$module=[IO.File]::ReadAllText($modulePath,[Text.Encoding]::UTF8)


$gateModule=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_prepreview_gate.jsxinc'),[Text.Encoding]::UTF8)


$bottomModule=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_bottom_plan.jsxinc'),[Text.Encoding]::UTF8)


$frontModule=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_frontmatter.jsxinc'),[Text.Encoding]::UTF8)


$apply=if($Mode -eq 'Apply'){'true'}else{'false'}


$configJson=$config|ConvertTo-Json -Depth 20 -Compress


$effectivePreview=if($ExportPreview){'Full'}else{$PreviewScope}


$previewJson=ConvertTo-Json -InputObject $effectivePreview -Compress


$exportIdmlJs=if($ExportIdml){'true'}else{'false'}


$closeWhenDoneJs=if($CloseWhenDone){'true'}else{'false'}


$script=$gateModule+$module+$bottomModule+$frontModule+@"





var __journalResult,__journalOldInteraction=app.scriptPreferences.userInteractionLevel;
app.scriptPreferences.userInteractionLevel=UserInteractionLevels.NEVER_INTERACT;


try {


 __journalResult=app.doScript(function(){


 var cfg=$configJson,target=File(cfg.documentPath),d=null,opened=false,targetPath=String(target.fsName).toLowerCase();


 function documentPath(document){try{return String(document.fullName.fsName).toLowerCase();}catch(e){throw Error('TARGET_PATH_UNAVAILABLE');}}


 function closeExact(document,saveOption){if(!document||!document.isValid)throw Error('TARGET_DOCUMENT_INVALID');if(documentPath(document)!==targetPath)throw Error('TARGET_PATH_CHANGED expected='+targetPath+' actual='+documentPath(document));if(document.id!==targetId)throw Error('TARGET_ID_CHANGED expected='+targetId+' actual='+document.id);document.close(saveOption);}


 for(var di=0;di<app.documents.length;di++){var candidate=app.documents[di].getElements()[0];try{if(String(candidate.fullName.fsName).toLowerCase()===targetPath){d=candidate;break;}}catch(ignore){}}


 if(!d){d=app.open(target);opened=true;}var targetId=d.id;if(documentPath(d)!==targetPath)throw Error('TARGET_PATH_CHANGED expected='+targetPath+' actual='+documentPath(d));


 if($apply&&!opened)throw Error('APPLY_TARGET_ALREADY_OPEN');


 if(cfg.articlePageRange){


  if($apply)throw Error('FULL_TARGET_CHECK_ONLY');


  for(var cbi=0;cbi<cfg.bindings.length;cbi++){var contractStory=d.stories.itemByID(cfg.bindings[cbi].id);if(!contractStory.isValid||contractStory.extractLabel('journal-template-contract')!==cfg.templateContractVersion)throw Error('ARTICLE_TEMPLATE_CONTRACT_MISMATCH '+cfg.bindings[cbi].id);}


 }else if(d.extractLabel('journal-template-contract')!==cfg.templateContractVersion)throw Error('TEMPLATE_CONTRACT_MISMATCH expected='+cfg.templateContractVersion+' actual='+d.extractLabel('journal-template-contract'));


 if($apply&&cfg.frontmatter){


  function roleStory(name){var found=[];for(var si=0;si<d.stories.length;si++)if(d.stories[si].extractLabel('journal-role')===name)found.push(d.stories[si]);if(found.length!==1)throw Error('FRONTMATTER_ROLE '+name+' '+found.length);return found[0];}


  function labeled(name){var found=[];for(var ii=0;ii<d.allPageItems.length;ii++)if(d.allPageItems[ii].label===name)found.push(d.allPageItems[ii]);if(found.length>1)throw Error('FRONTMATTER_LABEL '+name+' '+found.length);return found.length?found[0]:null;}


  var frontStory=roleStory('front'),footerStory=roleStory('footer'),bodyStory=roleStory('body'),bodyColumns=bodyStory.textContainers.everyItem().getElements();


  JournalFrontmatter.apply(d,{front:frontStory.textContainers[0],footer:footerStory.textContainers[0],bodyColumns:[bodyColumns[0],bodyColumns[1]],topGray:labeled('spacing-guide-top'),bottomGray:labeled('spacing-guide-bottom')||labeled('spacing-guide-footer'),separator:labeled('article-footer-separator')},cfg.frontmatter.data,cfg.frontmatter.config);


 }


 var result=JournalLayout.run(d,cfg,$apply);


 if($apply&&result.errors.length){closeExact(d,SaveOptions.NO);return 'AUDIT_WRITTEN document=opened preview=None applyFailed=true errors='+result.errors.length;}


 if($apply) d.save();


 var previewScope=$previewJson;


 if(result.errors.length)previewScope='None';


 if(previewScope!=='None'){


  var folder=Folder(File(cfg.auditPath).parent.fsName+'/'+d.name.replace(/\.indd$/i,'')+'_预览');if(!folder.exists)folder.create();


  if(cfg.articlePageRange){folder=Folder(folder.fsName+'/article-'+cfg.articlePageRange[0]+'-'+cfg.articlePageRange[1]);if(!folder.exists)folder.create();}


  var prefs=app.jpegExportPreferences,old=prefs.properties;


  try{prefs.exportResolution=150;prefs.jpegQuality=JPEGOptionsQuality.HIGH;prefs.exportingSpread=false;prefs.jpegExportRange=ExportRangeOrAllPages.EXPORT_RANGE;


   var first=cfg.articlePageRange?cfg.articlePageRange[0]:0,last=cfg.articlePageRange?cfg.articlePageRange[1]:d.pages.length-1,pages=[];


   if(previewScope==='Full'){for(var i=first;i<=last;i++)pages.push(i);}else{


    pages.push(first);pages.push(last);


    if(cfg.previewPageIndices)for(var pi=0;pi<cfg.previewPageIndices.length;pi++)pages.push(cfg.previewPageIndices[pi]);


    if(cfg.figurePanels)for(var fi=0;fi<cfg.figurePanels.length;fi++)if(cfg.figurePanels[fi].pageIndex!==undefined)pages.push(cfg.figurePanels[fi].pageIndex);


    if(cfg.formulaPageIndices)for(var qi=0;qi<cfg.formulaPageIndices.length;qi++)pages.push(cfg.formulaPageIndices[qi]);


   }


   var seen={};for(var ri=0;ri<pages.length;ri++){var pageIndex=Number(pages[ri]);if(pageIndex<first||pageIndex>last||seen[pageIndex])continue;seen[pageIndex]=true;prefs.pageString=d.pages[pageIndex].name;d.exportFile(ExportFormat.JPG,File(folder.fsName+'/page-'+(pageIndex-first+1)+'.jpg'),false);}


  }finally{prefs.properties=old;}


 }


 if($exportIdmlJs)d.exportFile(ExportFormat.INDESIGN_MARKUP,File(cfg.documentPath.replace(/\.indd$/i,'.idml')),false);


 if($closeWhenDoneJs&&opened)closeExact(d,SaveOptions.YES);


 return 'AUDIT_WRITTEN document='+(opened?'opened':'reused')+' preview='+previewScope;


 },ScriptLanguage.JAVASCRIPT,[],UndoModes.ENTIRE_SCRIPT,'Journal layout transaction');


}catch(e){__journalResult='ERROR '+e+' LINE '+e.line;}finally{app.scriptPreferences.userInteractionLevel=__journalOldInteraction;}


__journalResult;


"@


$reportPath=[IO.Path]::ChangeExtension($config.auditPath,'.result.json')


[IO.File]::WriteAllText($reportPath,'{"passed":false,"stage":"running"}',[Text.UTF8Encoding]::new($false))


$indesign=Get-Process InDesign -ErrorAction SilentlyContinue|Select-Object -First 1


if($indesign -and (-not $indesign.Responding -or $indesign.MainWindowTitle -match '^(Script Alert|脚本警告|脚本提示|警告)')){


 throw "InDesign has a blocking dialog or is not responding: $($indesign.MainWindowTitle)"


}


$app=New-Object -ComObject 'InDesign.Application.2020'


$result=(Invoke-JournalInDesignScript -Application $app -Code ($script))


if(-not ([string]$result).StartsWith('AUDIT_WRITTEN')){[IO.File]::WriteAllText($reportPath,(@{passed=$false;stage='native';error=[string]$result}|ConvertTo-Json));throw $result}


[xml]$audit=Get-Content -LiteralPath $config.auditPath -Raw -Encoding UTF8


$errors=[Collections.Generic.List[string]]::new()


foreach($errorNode in $audit.SelectNodes('/audit/error')){$errors.Add($errorNode.code+': '+$errorNode.InnerText)}


function Normalize([string]$s){[regex]::Replace($s,'[\s\uFFFC\u0016]','')}


foreach($observation in $audit.SelectNodes('/audit/observation')){


 if($observation.InnerText -match '^CONTINUED_TABLE (\d+) '){


  if(@($config.reviewedContinuedTables) -notcontains [int]$Matches[1]){$errors.Add('CONTINUATION_REVIEW '+$Matches[1]+' verify repeated header and continuation label before accepting')}


 }


}


$source=Get-Content -LiteralPath $config.sourceParagraphs -Raw -Encoding UTF8|ConvertFrom-Json


$actual=@($audit.SelectNodes('/audit/story/p'))


$matched=0;$scriptChars=0


foreach($p in $source){


 $expected=Normalize $p.text


 if($expected.StartsWith('Absrtact:')){$expected='Abstract:'+$expected.Substring(9)}


 $found=@($actual|Where-Object{(Normalize $_.GetAttribute('text')) -ceq $expected})


 if($found.Count -ne 1){$errors.Add("CONTENT paragraph $($p.index) matches=$($found.Count)");continue}


 $matched++


 foreach($kind in @('superscripts','subscripts')){


  $sourceRuns=@($p.$kind)


  if(-not $sourceRuns.Count){continue}


  $position=if($kind -eq 'superscripts'){'1936749411'}else{'1935831907'}


  $expectedRuns=Normalize ($sourceRuns -join '')


  $actualRuns=Normalize (($found[0].r|Where-Object{[string]$_.position -eq $position}|ForEach-Object{$_.InnerText}) -join '')


  if($expectedRuns -cne $actualRuns){$errors.Add("SCRIPT_POSITION paragraph $($p.index) $kind expected=$expectedRuns actual=$actualRuns")}


  $scriptChars+=$expectedRuns.Length


 }


}


$rawTables=Get-Content -LiteralPath $config.sourceTables -Raw -Encoding UTF8|ConvertFrom-Json


$tables=@(if($null -ne $rawTables -and $rawTables.PSObject.Properties['tables']){$rawTables.tables}else{$rawTables})


$actualTables=@($audit.SelectNodes('/audit/table'));$cells=0;$mergedEmptyCells=0


if($actualTables.Count -ne $tables.Count){$errors.Add('CONTENT table count')}


for($i=0;$i -lt $tables.Count;$i++){


 $rows=@($tables[$i].rows)


 if($i -ge $actualTables.Count){continue}


 if([int]$actualTables[$i].rows -ne $rows.Count){$errors.Add("CONTENT table $i rows")}


 for($r=0;$r -lt $rows.Count;$r++){


  for($c=0;$c -lt $rows[$r].Count;$c++){


   $merge=@($config.mergedEmptyCells|Where-Object{$_.tableIndex -eq $i -and $_.rowIndex -eq $r -and $_.cellIndex -eq $c})


   if($merge.Count){


    if($merge.Count -ne 1 -or (Normalize ([string]$rows[$r][$c])) -ne ''){throw "Only one verified empty source cell may be merged: $i/$r/$c"}


    $targetRows=@($actualTables[$i].SelectNodes('row'))


    $targetCells=@($targetRows[$merge[0].intoRow].SelectNodes('cell'))


    $targetSkipped=@($config.mergedEmptyCells|Where-Object{$_.tableIndex -eq $i -and $_.rowIndex -eq $merge[0].intoRow -and $_.cellIndex -lt $merge[0].intoCell}).Count

    $targetColumn=[int]$merge[0].intoCell-$targetSkipped

    $expectedSpan=if($merge[0].PSObject.Properties['expectedRowSpan']){[int]$merge[0].expectedRowSpan}else{2}

    if($expectedSpan -lt 2 -or $merge[0].intoRow -ge $r -or $r-$merge[0].intoRow -ge $expectedSpan){throw "Invalid source merge span: $i/$r/$c"}

    if($targetColumn -lt 0 -or $targetColumn -ge $targetCells.Count -or [int]$targetCells[$targetColumn].GetAttribute('rowSpan') -ne $expectedSpan){$errors.Add("CONTENT merge span $i/$r/$c")}


    $mergedEmptyCells++;continue


   }


   $skipped=@($config.mergedEmptyCells|Where-Object{$_.tableIndex -eq $i -and $_.rowIndex -eq $r -and $_.cellIndex -lt $c}).Count


   $actualColumn=$c-$skipped


   $nodes=@($actualTables[$i].SelectNodes('row'))


   if($r -ge $nodes.Count){$errors.Add("CONTENT table $i row $r missing");continue}


   $cellNodes=@($nodes[$r].SelectNodes('cell'))


   if($actualColumn -ge $cellNodes.Count -or (Normalize ([string]$rows[$r][$c])) -cne (Normalize $cellNodes[$actualColumn].GetAttribute('text'))){$errors.Add("CONTENT cell $i/$r/$c")}


   $cells++


  }


 }


}


foreach($asset in @($config.assets)){


 if(-not(Test-Path -LiteralPath $asset.path)){$errors.Add('ASSET_MISSING '+$asset.name);continue}


 if((Get-FileHash -LiteralPath $asset.path -Algorithm SHA256).Hash -ine $asset.sha256){$errors.Add('ASSET_CHANGED '+$asset.name)}


}


$summary=[ordered]@{document=$config.documentPath;mode=$Mode;passed=($errors.Count -eq 0);pages=[int]$audit.audit.pages;paragraphsMatched=$matched;paragraphsExpected=$source.Count;cellsCompared=$cells;mergedEmptyCells=$mergedEmptyCells;scriptCharactersChecked=$scriptChars;errors=@($errors);moduleSHA256=(Get-FileHash -LiteralPath $modulePath -Algorithm SHA256).Hash}


$reportPath=[IO.Path]::ChangeExtension($config.auditPath,'.result.json')


[IO.File]::WriteAllText($reportPath,($summary|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))


$summary|ConvertTo-Json -Depth 10


if($errors.Count -and -not($AllowValidationFailure -and $Mode -eq 'Check')){throw "Layout validation failed: $($errors.Count) errors. See $reportPath"}
