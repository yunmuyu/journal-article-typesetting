param([Parameter(Mandatory=$true)][string]$ConfigPath,[Parameter(Mandatory=$true)][string]$ReportPath,[Parameter(Mandatory=$true)][string]$DuplicateFigurePath)
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$config=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8|ConvertFrom-Json
$fixture=Join-Path (Split-Path -Parent $ReportPath) 'title_link_fixture_QA.indd'
if(Test-Path -LiteralPath $fixture){throw 'Fixture already exists'}
Copy-Item -LiteralPath $config.documentPath -Destination $fixture
$config.documentPath=$fixture.Replace('\','/')
$json=$config|ConvertTo-Json -Depth 30 -Compress
$duplicate=ConvertTo-Json -InputObject $DuplicateFigurePath.Replace('\','/') -Compress
$module=[IO.File]::ReadAllText((Join-Path $project '2-导入_InDesign\journal_layout_rules.jsxinc'))
$app=New-Object -ComObject InDesign.Application.2020
$script=$module+"`nvar cfg="+$json+";var duplicate="+$duplicate+@"
;
(function(){var d=app.open(File(cfg.documentPath),false),out=[];try{
JournalLayout.bind(d,cfg);var front=null;for(var i=0;i<cfg.bindings.length;i++)if(cfg.bindings[i].role==='front')front=d.stories.itemByID(cfg.bindings[i].id);var title=null;for(var i=0;i<front.paragraphs.length;i++)if(front.paragraphs[i].appliedParagraphStyle.name==='英语大标题'||front.paragraphs[i].appliedParagraphStyle.name==='英文大标题')title=front.paragraphs[i];if(!title||title.lines.length!==2)throw Error('Two-line title fixture required');
function has(code){var r=JournalLayout.audit(d,cfg);for(var i=0;i<r.errors.length;i++)if(r.errors[i].code===code)return true;return false;}
title.leading=14.1;d.recompose();front.textContainers[0].fit(FitOptions.FRAME_TO_CONTENT);if(!has('EN_TITLE_LAST_LEADING')||!has('EN_TITLE_AUTHOR_GAP'))throw Error('Compressed author gap escaped');out.push('PASS rejects whole-title leading compression');
JournalLayout.applyTypography(d,cfg);d.recompose();front.textContainers[0].fit(FitOptions.FRAME_TO_CONTENT);if(has('EN_TITLE_LAST_LEADING')||has('EN_TITLE_AUTHOR_GAP'))throw Error('Title repair failed');if(Math.abs(Number(title.lines[0].leading)-14.1)>.001)throw Error('Upper line adjustment lost');out.push('PASS restores last-line spacing and preserves upper-line adjustment');
var first=null;for(var i=0;i<cfg.assets.length;i++)if(cfg.assets[i].kind==='figure'){first=cfg.assets[i];break;}var link=d.links.itemByName(first.name);link.relink(File(duplicate));if(!has('ORIGINAL_FIGURE_LINK'))throw Error('Duplicate figure link escaped');out.push('PASS rejects duplicate figure path with original basename');
d.links.itemByName(first.name).relink(File(first.source));if(has('ORIGINAL_FIGURE_LINK'))throw Error('Direct original links rejected');out.push('PASS accepts all direct original figure links');return out.join(String.fromCharCode(10));
}catch(e){return 'ERROR '+e+' LINE '+e.line;}finally{d.close(SaveOptions.NO);}})();
"@
try{$result=[string]$app.DoScript($script,1246973031);if($result.StartsWith('ERROR')){throw $result};[IO.File]::WriteAllText($ReportPath,$result,[Text.UTF8Encoding]::new($false));$result}finally{Remove-Item -LiteralPath $fixture -Force}