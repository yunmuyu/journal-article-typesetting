param([string]$ImporterPath)
$ErrorActionPreference='Stop'
if(-not $ImporterPath){$ImporterPath=Join-Path (Split-Path -Parent $PSScriptRoot) '2-导入_InDesign\import_word_article_to_indesign.jsx'}
$source=[IO.File]::ReadAllText($ImporterPath)
$path=(Join-Path $PSScriptRoot 'journal_roles_input.json').Replace('\','/')
$source=[regex]::Replace($source,'File\.openDialog\([^;]*\);',('File("'+$path+'");'),1)
$script=@"
var alert=function(){};var d=app.activeDocument,frame=null,out='';
if(!/QA|copy|副本/i.test(d.name))throw Error('QA required');
try{
 frame=d.textFrames.add({geometricBounds:[-200,-100,-80,100]});app.select(frame);
 $source
 var s=frame.parentStory;
 if(String(s.paragraphs[0].contents).indexOf('Abstract:')!==0)throw Error('Label spelling');
 for(var i=0;i<2;i++){var p=s.paragraphs[i],label=p.characters[0],body=p.characters[-2];
  if(label.appliedFont.fontFamily!=='思源黑体 CN'||label.fontStyle!=='Bold'||label.pointSize!==9||label.leading!==13)throw Error('English label role');
  if(String(body.appliedFont.name).split('\t')[0]!=='现 宋体-1'||body.pointSize!==9||body.leading!==13)throw Error('English body role');
 }
 var label=s.paragraphs[2].characters[0],body=s.paragraphs[2].characters[-2];
 if(String(label.appliedFont.name).split('\t')[0]!=='现 黑体'||label.pointSize!==12||label.leading!==16)throw Error('Bio label role');
 if(body.appliedFont.fontFamily!=='楷体'||body.pointSize!==9||body.leading!==13||s.paragraphs[2].spaceBefore!==0)throw Error('Bio body role');
 var body=s.paragraphs[3].characters[0];if(String(body.appliedFont.name).split('\t')[0]!=='现 宋体-1'||body.pointSize!==10.5||body.leading!==15)throw Error('Body role');
 out='PASS English labels/body, author label/body, typo-only fix and body default';
}catch(e){out='ERROR '+e+' line '+e.line;}finally{if(frame&&frame.isValid)frame.remove();}
out;
"@
$app=New-Object -ComObject 'InDesign.Application.2020'
$result=$app.DoScript($script,1246973031)
if($result -notlike 'PASS*'){throw $result}
$result