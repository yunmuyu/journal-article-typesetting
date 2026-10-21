param(
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [ValidateRange(6,8)][int]$PageCount=8,
    [ValidateRange(0,10000)][int]$StartPageIndex=0,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$BodyStyleName,
    [switch]$ValidateOnly
)
Import-Module (Join-Path $PSScriptRoot 'JournalInDesignScript.psm1') -Force
$ErrorActionPreference='Stop'
$source=(Get-Item -LiteralPath $SourcePath).FullName
if([IO.Path]::GetExtension($source) -ine '.indd'){throw 'SourcePath must be an INDD document'}
$output=[IO.Path]::GetFullPath($OutputPath)
if([IO.Path]::GetExtension($output) -ine '.indd'){throw 'OutputPath must end in .indd'}
if([IO.Path]::GetFileName($output) -notmatch '(QA|copy|副本)'){throw 'OutputPath must be an explicit QA/copy/副本'}
if($source -ieq $output){throw 'Source and output must be different files'}
$parent=Split-Path -Parent $output
if(-not(Test-Path -LiteralPath $parent -PathType Container)){throw 'Output directory does not exist'}
$jsxPath=Join-Path $PSScriptRoot 'initialize_journal_qa_template.jsx'
if(-not(Test-Path -LiteralPath $jsxPath -PathType Leaf)){throw 'Initializer JSX is missing'}
$sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
$jsxHash=(Get-FileHash -LiteralPath $jsxPath -Algorithm SHA256).Hash
$manifestPath=$output+'.template.json'
$identity=[ordered]@{sourcePath=$source;sourceSha256=$sourceHash;pageCount=$PageCount;startPageIndex=$StartPageIndex;bodyStyleName=$BodyStyleName;initializerSha256=$jsxHash;slotSchemaVersion='3'}
if(Test-Path -LiteralPath $output){
    if(-not(Test-Path -LiteralPath $manifestPath)){throw 'OUTPUT_EXISTS without a template manifest; choose another QA path'}
    $old=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
    $same=$true
    foreach($name in $identity.Keys){if([string]$old.$name -cne [string]$identity[$name]){$same=$false}}
    $currentOutputHash=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
    if($same -and $old.outputSha256 -ceq $currentOutputHash){
        [ordered]@{status='reused';outputPath=$output;manifestPath=$manifestPath;outputSha256=$currentOutputHash;sourceUnchanged=$true}|ConvertTo-Json -Depth 5
        return
    }
    throw 'OUTPUT_EXISTS with different inputs or changed content; choose another QA path'
}
if($ValidateOnly){
    [ordered]@{status='validated';sourcePath=$source;outputPath=$output;pageCount=$PageCount;startPageIndex=$StartPageIndex;bodyStyleName=$BodyStyleName;sourceSha256=$sourceHash;initializerSha256=$jsxHash;slotSchemaVersion='3'}|ConvertTo-Json -Depth 5
    return
}
$job=[ordered]@{sourcePath=$source;outputPath=$output;pageCount=$PageCount;startPageIndex=$StartPageIndex;bodyStyleName=$BodyStyleName;preserveRoles=@('front','body','footer','doi')}
$jobJson=$job|ConvertTo-Json -Depth 5 -Compress
$jsx=[IO.File]::ReadAllText($jsxPath,[Text.Encoding]::UTF8)+"`r`nvar JournalQaTemplateResult=JournalQaTemplate.run($jobJson); JournalQaTemplateResult;"
$sourceStamp=(Get-Item -LiteralPath $source).LastWriteTimeUtc
$app=New-Object -ComObject 'InDesign.Application.2020'
$nativeResult=[string](Invoke-JournalInDesignScript -Application $app -Code ($jsx))
if(-not(Test-Path -LiteralPath $output -PathType Leaf)){throw "Template creation failed: $nativeResult"}
$result=$nativeResult|ConvertFrom-Json
if($result.status -ne 'created' -or [int]$result.pages -ne $PageCount){throw "Unexpected initializer result: $nativeResult"}
foreach($slot in @('front-title','front-abstract','body-left','body-right','received-fund','doi')){
    if($null -eq $result.slots.$slot){throw "Template slot missing: $slot"}
}
$sourceAfter=Get-FileHash -LiteralPath $source -Algorithm SHA256
if($sourceAfter.Hash -cne $sourceHash -or (Get-Item -LiteralPath $source).LastWriteTimeUtc -ne $sourceStamp){throw 'SOURCE_CHANGED during template creation'}
$manifest=[ordered]@{}
foreach($name in $identity.Keys){$manifest[$name]=$identity[$name]}
$manifest.outputPath=$output
$manifest.outputSha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
$manifest.createdAt=(Get-Date).ToString('o')
$manifest.native=$result
[IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
[ordered]@{status='created';outputPath=$output;manifestPath=$manifestPath;outputSha256=$manifest.outputSha256;sourceUnchanged=$true;native=$result}|ConvertTo-Json -Depth 10
