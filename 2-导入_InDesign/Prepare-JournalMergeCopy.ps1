[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$StyleToken,
    [Parameter(Mandatory=$true)][string]$ReportPath,
    [string]$ApprovedTemplatePath,
    [string]$CharacterStyleAuthorityPath
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'JournalInDesignScript.psm1') -Force
$source=[IO.Path]::GetFullPath($SourcePath);$target=[IO.Path]::GetFullPath($OutputPath)
if($source -eq $target){throw 'MERGE_COPY_EQUALS_SOURCE'}
if([IO.Path]::GetFileName($target) -notmatch '(QA|copy|副本)'){throw 'MERGE_QA_REQUIRED'}
if(Test-Path -LiteralPath $target){throw 'MERGE_COPY_ALREADY_EXISTS'}
$sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ReportPath)))
$authorityHash=if($CharacterStyleAuthorityPath){(Get-FileHash -LiteralPath $CharacterStyleAuthorityPath -Algorithm SHA256).Hash}else{$null}
$spec=@{source=$source;target=$target;token=$StyleToken;template=$ApprovedTemplatePath;characterAuthority=$CharacterStyleAuthorityPath}|ConvertTo-Json -Compress
$code=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_regression_snapshot.jsxinc'))+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_merge_safety.jsxinc'))+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_frontmatter.jsxinc'))+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_layout_rules.jsxinc'))+@"
var JournalMergeCopySpec=$spec;
"@+@'
(function(spec){var oldUI=app.scriptPreferences.userInteractionLevel,oldRedraw=app.scriptPreferences.enableRedraw;try{
app.scriptPreferences.userInteractionLevel=UserInteractionLevels.NEVER_INTERACT;app.scriptPreferences.enableRedraw=false;
var input=File(spec.source),output=File(spec.target),source=null;
for(var i=0;i<app.documents.length;i++)if(app.documents[i].fullName.fsName===input.fsName)source=app.documents[i];
var sourceModified=source?source.modified:null;
if(source)source.saveACopy(output);else if(!input.copy(output.fsName))throw Error('MERGE_COPY_FAILED');
var d=app.open(output,false),bindings=[];
for(var i=0;i<d.stories.length;i++){var s=d.stories[i],role=s.extractLabel('journal-role');if(role)bindings.push({id:s.id,role:role});}
if(!bindings.length)throw Error('MERGE_BINDINGS_REQUIRED');
var affiliationRepair=null;
if(spec.template){
    var templateFile=File(spec.template),template=null;
    for(var ti=0;ti<app.documents.length;ti++)if(app.documents[ti].fullName.fsName===templateFile.fsName)template=app.documents[ti];
    if(!template)template=app.open(templateFile,false);
    var expected=null,templateStyles=template.allParagraphStyles;
    for(var ti=0;ti<templateStyles.length;ti++)if(templateStyles[ti].name==='英文作者单位')expected=Number(templateStyles[ti].leading);
    if(expected!==25)throw Error('APPROVED_AFFILIATION_STYLE_CONTRACT');
    var styles=d.allParagraphStyles,front=null,body=null,guide=null,count=0,texts=[];
    for(var ti=0;ti<styles.length;ti++)if(styles[ti].name==='英文作者单位')styles[ti].leading=expected;
    for(var ti=0;ti<d.stories.length;ti++){var story=d.stories[ti];texts.push(String(story.contents));if(story.extractLabel('journal-role')==='front')front=story.textContainers[0];if(story.extractLabel('journal-role')==='body')body=story;for(var pi=0;pi<story.paragraphs.length;pi++)if(story.paragraphs[pi].appliedParagraphStyle.name==='英文作者单位'){JournalLayout.applyEnglishAffiliationSpacing(story.paragraphs[pi]);count++;}}
    var items=d.allPageItems;for(var ti=0;ti<items.length;ti++)if(items[ti].label==='spacing-guide-top')guide=items[ti];
    if(count!==1||!front||!body)throw Error('AFFILIATION_BINDING');
    affiliationRepair=JournalFrontmatter.refitExistingFront(d,front,body.textContainers,guide);
    affiliationRepair.finalPageRecovery=JournalLayout.prepareFinalPageReflow(d);
    for(var ti=0;ti<d.stories.length;ti++)if(String(d.stories[ti].contents)!==texts[ti])throw Error('AFFILIATION_TEXT_CHANGED');
}
var scope={articlePageRange:[0,d.pages.length-1],bindings:bindings},before=JournalRegressionSnapshot.capture(d,scope);
var characterStyleAdoption=null;if(spec.characterAuthority){JournalMergeSafety.restoreCharacterStyleRoots(d);characterStyleAdoption=JournalMergeSafety.adoptAuthoritativeCharacterStyles(d,File(spec.characterAuthority),null,true);}
var beforeNamespace=JournalRegressionSnapshot.capture(d,scope),namespace=JournalMergeSafety.prepare(d,spec.token),after=JournalRegressionSnapshot.capture(d,scope);
if(JournalRegressionSnapshot.json(beforeNamespace.stories)!==JournalRegressionSnapshot.json(after.stories))throw Error('MERGE_NAMESPACE_CHANGED_STORY_FORMAT');
if(JournalRegressionSnapshot.json(beforeNamespace.objects)!==JournalRegressionSnapshot.json(after.objects))throw Error('MERGE_NAMESPACE_CHANGED_OBJECTS');
if(source&&source.modified!==sourceModified)throw Error('MERGE_SOURCE_STATE_CHANGED');
d.save();return JournalRegressionSnapshot.json({status:'prepared-not-final-passed',documentId:d.id,path:output.fsName,sourceMemoryCopied:!!source,sourceModified:sourceModified,namespace:namespace,characterStyleAdoption:characterStyleAdoption,affiliationRepair:affiliationRepair,namespaceFormatPreserved:true,bindings:bindings});
}finally{app.scriptPreferences.userInteractionLevel=oldUI;app.scriptPreferences.enableRedraw=oldRedraw;}})(JournalMergeCopySpec);
'@
$app=New-Object -ComObject InDesign.Application.2020
$raw=[string](Invoke-JournalInDesignScript -Application $app -Code $code)
if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $sourceHash){throw 'MERGE_SOURCE_FILE_CHANGED'}
if($CharacterStyleAuthorityPath -and (Get-FileHash -LiteralPath $CharacterStyleAuthorityPath -Algorithm SHA256).Hash -ne $authorityHash){throw 'CHARACTER_AUTHORITY_FILE_CHANGED'}
$result=$raw|ConvertFrom-Json
if($CharacterStyleAuthorityPath){
    Import-Module (Join-Path $PSScriptRoot 'JournalCharacterDefinitionEvidence.psm1') -Force
    $evidence=New-JournalCharacterDefinitionEvidence -Application $app -SourceId $result.documentId -TargetId $result.characterStyleAdoption.authorityDocumentId -AuthorityId $result.characterStyleAdoption.authorityDocumentId -Directory ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ReportPath)))
    $verify=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_merge_safety.jsxinc'))+$evidence+';JournalMergeSafety.characterStyleConflicts(app.documents.itemByID('+$result.documentId+'),app.documents.itemByID('+$result.characterStyleAdoption.authorityDocumentId+')).join(",");'
    $conflicts=[string](Invoke-JournalInDesignScript -Application $app -Code $verify)
    if($conflicts){throw "CHARACTER_AUTHORITY_DEFINITION_MISMATCH $conflicts"}
    $result.characterStyleAdoption.definitionsCompared=$true
}
$result|Add-Member -NotePropertyName sourceSHA256 -NotePropertyValue $sourceHash
[IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath),($result|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
$result
