$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$entry=Join-Path $root '2-导入_InDesign\Initialize-JournalQaTemplate.ps1'
$jsx=Join-Path $root '2-导入_InDesign\initialize_journal_qa_template.jsx'
$text=[IO.File]::ReadAllText($jsx,[Text.Encoding]::UTF8)
if($text -match '\b(alert|confirm|prompt)\s*\('){throw 'Interactive dialog call found in initializer'}
if($text -notmatch 'UserInteractionLevels\.NEVER_INTERACT'){throw 'Missing noninteractive mode'}
if($text -notmatch 'sourceOpenedHere\s*&&\s*source'){throw 'Source-close ownership guard missing'}
if($text -notmatch 'function\s+closeExact' -or $text -notmatch 'TARGET_PATH_CHANGED' -or $text -notmatch 'TARGET_ID_CHANGED'){throw 'Exact document close guard missing'}
if($text -match '\btarget\.close\(' -or $text -match '\bsource\.close\('){throw 'Direct document close bypasses identity guard'}
if($text -match '\bsource\.save\s*\('){throw 'Initializer may not save source'}
if($text -notmatch 'source\.saveACopy\(outputFile\)' -or $text -notmatch 'normalizeBodyPages'){throw 'Template must preserve the accepted document environment and normalize article-specific body frames'}
if($text -match 'app\.documents\.add\(' -or $text -match '\.duplicate\(LocationOptions'){throw 'Template initializer rebuilt or duplicated pages instead of copying the accepted environment'}
if($text -notmatch 'verifyCompositeFonts' -or $text -notmatch 'COMPOSITE_FONT_MISMATCH'){throw 'Composite font verification is missing'}
if($text -notmatch 'readEntryProperty' -or $text -notmatch 'COMPOSITE_FONT_UNVERIFIABLE'){throw 'Safe composite font property reads are missing'}
if($text -match 'entry\.customCharacters' -or $text -match 'entry\.scaleOption'){throw 'Unstable composite font properties are read directly'}
foreach($property in @('appliedFont','fontStyle','relativeSize','horizontalScale','verticalScale','baselineShift')){if($text.IndexOf('"'+$property+'"',[StringComparison]::Ordinal) -lt 0){throw "Stable composite property missing: $property"}}
if($text -notmatch 'isCompositeFontSentinel' -or $text -notmatch 'no composite font' -or $text -notmatch '无复合字体'){throw 'InDesign composite font sentinel is not excluded'}
if($text -notmatch 'journal-role' -or $text -notmatch 'spacing-guide'){throw 'Fixed-anchor retention is missing'}
if($text -notmatch 'structuralInventory' -or $text -notmatch 'geometricBounds'){throw 'Anchor geometry inventory is missing'}
foreach($slot in @('front-title','front-abstract','body-left','body-right','received-fund','doi')){
    if($text.IndexOf('"'+$slot+'"',[StringComparison]::Ordinal) -lt 0){throw "Required template slot missing: $slot"}
}
if($text -notmatch 'journal-slot-aliases' -or $text -notmatch 'SLOT_COUNT'){throw 'Explicit slot registration and validation are missing'}
if($text -notmatch 'verifyBodyStyle' -or $text -notmatch 'BODY_STYLE_METRICS' -or $text -notmatch 'journal-body-style'){throw 'Verified 10.5/15 body-style binding is missing'}
if($text -notmatch 'removeUnscopedPasteboardStories' -or $text -notmatch 'PASTEBOARD_STORY_REMAINS'){throw 'Unscoped pasteboard story cleanup is missing'}
if($text -notmatch 'normalizeLegacyBodyStyles' -or $text -notmatch 'LEGACY_BODY_STYLE_METRICS'){throw 'Legacy body style normalization is missing'}
if($text -notmatch 'journal-template-contract' -or $text -notmatch 'qa-template-contract-v2'){throw 'Template contract version label is missing'}
if($text -notmatch 'insetSpacing\s*=\s*\[0,\s*0,\s*0,\s*0\]' -or $text -notmatch 'VerticalJustification\.TOP_ALIGN'){throw 'Body frame normalization is incomplete'}
foreach($guard in @('FIXED_DOI','FIXED_FRONT','FIXED_FOOTER','FIXED_FIRST_BODY_LEFT','FIXED_FIRST_BODY_RIGHT','journal-fixed-geometry')){if($text.IndexOf($guard,[StringComparison]::Ordinal) -lt 0){throw "Fixed geometry guard missing: $guard"}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('journal-qa-template-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp|Out-Null
try{
    $source=Join-Path $temp 'approved-source.indd';[IO.File]::WriteAllBytes($source,[byte[]](1,2,3,4))
    $output=Join-Path $temp 'blank-QA.indd'
    $bodyStyle='期刊正文_已通过_测试'
    $plan=& $entry -SourcePath $source -OutputPath $output -PageCount 7 -StartPageIndex 3 -BodyStyleName $bodyStyle -ValidateOnly|ConvertFrom-Json
    if($plan.status -ne 'validated' -or $plan.pageCount -ne 7 -or $plan.startPageIndex -ne 3 -or $plan.bodyStyleName -ne $bodyStyle -or $plan.slotSchemaVersion -ne '3'){throw 'ValidateOnly plan mismatch'}
    if(Test-Path -LiteralPath $output){throw 'ValidateOnly touched output'}
    $failed=$false
    try{& $entry -SourcePath $source -OutputPath (Join-Path $temp 'unsafe.indd') -PageCount 7 -BodyStyleName $bodyStyle -ValidateOnly|Out-Null}catch{$failed=$true}
    if(-not$failed){throw 'Unsafe output name was accepted'}
    $failed=$false
    try{& $entry -SourcePath $source -OutputPath $output -PageCount 5 -BodyStyleName $bodyStyle -ValidateOnly|Out-Null}catch{$failed=$true}
    if(-not$failed){throw 'Out-of-range page count was accepted'}
    if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $plan.sourceSha256){throw 'ValidateOnly changed source'}
    [IO.File]::WriteAllBytes($output,[byte[]](5,6,7,8))
    $manifest=[ordered]@{sourcePath=$plan.sourcePath;sourceSha256=$plan.sourceSha256;pageCount=7;startPageIndex=3;bodyStyleName=$bodyStyle;initializerSha256=$plan.initializerSha256;slotSchemaVersion='3';outputSha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash}
    [IO.File]::WriteAllText($output+'.template.json',($manifest|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    $reused=& $entry -SourcePath $source -OutputPath $output -PageCount 7 -StartPageIndex 3 -BodyStyleName $bodyStyle|ConvertFrom-Json
    if($reused.status -ne 'reused' -or $reused.outputSha256 -ne $manifest.outputSha256){throw 'Idempotent reuse failed'}
    Write-Output 'PASS QA template initializer is noninteractive, source-safe, range-limited and dry-run verifiable.'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}
