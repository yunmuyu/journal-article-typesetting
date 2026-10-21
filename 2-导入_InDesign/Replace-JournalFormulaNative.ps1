param([Parameter(Mandatory=$true)][string]$ConfigPath,[Parameter(Mandatory=$true)][int[]]$Numbers,[string]$SourceAi,[string]$BackupDirectory)
Import-Module (Join-Path $PSScriptRoot 'JournalInDesignScript.psm1') -Force
$ErrorActionPreference='Stop'
$configFile=(Get-Item -LiteralPath $ConfigPath).FullName
$config=Get-Content -LiteralPath $configFile -Raw -Encoding UTF8|ConvertFrom-Json
if([IO.Path]::GetFileName($config.documentPath) -notmatch '(QA|copy|副本)'){throw 'QA_COPY_REQUIRED'}
if($SourceAi -and $Numbers.Count -ne 1){throw 'SourceAi override is for one formula only'}
if(-not $BackupDirectory){$BackupDirectory=Join-Path ([IO.Path]::GetDirectoryName($configFile)) ('恢复副本\原生公式_'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff'))}
[void][IO.Directory]::CreateDirectory($BackupDirectory)
$indesign=New-Object -ComObject InDesign.Application.2020
$illustrator=New-Object -ComObject Illustrator.Application.CC.2019
$snapshot=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_regression_snapshot.jsxinc'),[Text.Encoding]::UTF8)
$rules=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_layout_rules.jsxinc'),[Text.Encoding]::UTF8)
$targetJson=ConvertTo-Json -Compress -InputObject ([string]$config.documentPath)
$backupJson=ConvertTo-Json -Compress -InputObject (Join-Path $BackupDirectory ([IO.Path]::GetFileName($config.documentPath)))
$target=[string](Invoke-JournalInDesignScript -Application $indesign -Code ("(function(){var f=File($targetJson),d=null;for(var i=0;i<app.documents.length;i++){var candidate=app.documents[i].getElements()[0];try{if(candidate.fullName.fsName.toLowerCase()===f.fsName.toLowerCase())d=candidate;}catch(e){}}if(!d)d=app.open(f,false);var backup=File($backupJson);if(backup.exists)throw Error('BACKUP_EXISTS');d.saveACopy(backup);return d.id;})();"))
$documentId=[int]$target
$results=@();$removedLinks=0
foreach($number in $Numbers){
 $asset=@($config.assets|Where-Object {$_.kind -eq 'formula' -and [int]$_.number -eq $number})
 if($asset.Count -ne 1){throw "FORMULA_ASSET_COUNT $number"}
 $aiPath=if($SourceAi){(Get-Item -LiteralPath $SourceAi).FullName}else{[IO.Path]::ChangeExtension([string]$asset[0].path,'.ai')}
 if(-not(Test-Path -LiteralPath $aiPath)){throw "FORMULA_AI_MISSING $number"}
 $aiJson=ConvertTo-Json -Compress -InputObject $aiPath
 $copy=[string]$illustrator.DoJavaScript("(function(){var f=File($aiJson);for(var i=0;i<app.documents.length;i++){try{if(app.documents[i].fullName.fsName===f.fsName)throw Error('SOURCE_ALREADY_OPEN');}catch(e){if(String(e).indexOf('SOURCE_ALREADY_OPEN')>=0)throw e;}}var d=app.open(f);try{if(d.textFrames.length)throw Error('FORMULA_NOT_OUTLINED');d.selectObjectsOnActiveArtboard();app.copy();return 'COPIED';}finally{d.close(SaveOptions.DONOTSAVECHANGES);}}());")
 if($copy -ne 'COPIED'){throw 'FORMULA_COPY_FAILED'}
 $job=@{documentId=$documentId;documentPath=$config.documentPath;number=$number;sourceAi=$aiPath;sourceSha256=(Get-FileHash -LiteralPath $aiPath -Algorithm SHA256).Hash;articlePageRange=$config.articlePageRange}|ConvertTo-Json -Compress
 $entry=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'replace_formula_native.jsx'),[Text.Encoding]::UTF8)
 $answer=[string](Invoke-JournalInDesignScript -Application $indesign -Code ($snapshot+"`n"+$rules+"`nvar JournalFormulaReplaceJob=$job;"+$entry))
 $result=$answer|ConvertFrom-Json;if(-not $result.passed){throw $answer};$results+=@($result);$removedLinks+=[int]$result.oldGraphics
 $asset[0].path=$aiPath;$asset[0].sha256=(Get-FileHash -LiteralPath $aiPath -Algorithm SHA256).Hash;$asset[0]|Add-Member -NotePropertyName placement -NotePropertyValue 'native-vector' -Force;$asset[0].width=[double]$result.newBounds[3]-[double]$result.newBounds[1];$asset[0].height=[double]$result.newBounds[2]-[double]$result.newBounds[0]
}
$config.graphicCount=[int]$config.graphicCount-$removedLinks
$config|Add-Member -NotePropertyName requireNativeFormulaPaste -NotePropertyValue $true -Force
[IO.File]::WriteAllText($configFile,($config|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
$report=Join-Path $BackupDirectory '原生公式替换记录.json'
[IO.File]::WriteAllText($report,($results|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
$results|ConvertTo-Json -Depth 12
