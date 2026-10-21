$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$modulePath=Join-Path $root '2-导入_InDesign\journal_slot_template.jsxinc'
$entryPath=Join-Path $root '2-导入_InDesign\Invoke-JournalSlotAssembly.ps1'
$module=[IO.File]::ReadAllText($modulePath,[Text.Encoding]::UTF8)
$entry=[IO.File]::ReadAllText($entryPath,[Text.Encoding]::UTF8)
foreach($slot in @('front-title','front-abstract','body-left','body-right','received-fund','doi')){
    if($module.IndexOf('"'+$slot+'"',[StringComparison]::Ordinal) -lt 0){throw "Slot contract missing $slot"}
}
foreach($kind in @('formula','doi','received-fund','gray','continued-table')){
    if($module.IndexOf($kind,[StringComparison]::Ordinal) -lt 0){throw "Component kind missing $kind"}
}
foreach($token in @('exportFile(ExportFormat.INDESIGN_SNIPPET','duplicate(targetPage)','targetPage.place(file)','journal-component-key','journal-component-hash','COMPONENT_IDENTITY')){
    if($module.IndexOf($token,[StringComparison]::Ordinal) -lt 0){throw "Native component contract missing $token"}
}
if($module -match '\.textFrames\.add\s*\(' -or $module -match '\.rectangles\.add\s*\('){throw 'Slot assembly must not recreate first-page frames'}
if(([regex]::Matches($entry,'Invoke-JournalInDesignScript -Application')).Count -ne 1){throw 'Assembly entry must use exactly one cross-process JSX call'}
if($entry -notmatch 'enableRedraw=false' -or $entry -notmatch 'preflightOff=true'){throw 'Redraw or background preflight is not suspended'}
if($entry -match '\b(alert|confirm|prompt)\s*\('){throw 'Interactive dialog call found'}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('journal-slot-plan-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp|Out-Null
try{
    $document=Join-Path $temp 'article-QA.indd';[IO.File]::WriteAllBytes($document,[byte[]](1,2,3))
    $idms=Join-Path $temp 'doi.idms';[IO.File]::WriteAllBytes($idms,[byte[]](4,5,6))
    $config=Join-Path $temp 'slot.json'
    @{documentPath=$document;doiText='DOI: sample';components=@(@{mode='idms';kind='doi';key='doi-v1';hash='content-hash';idmsPath=$idms;sha256=(Get-FileHash $idms -Algorithm SHA256).Hash;pageIndex=0})}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $config -Encoding UTF8
    $plan=& $entryPath -ConfigPath $config -PlanOnly|ConvertFrom-Json
    if($plan.status -ne 'ready' -or -not $plan.singleJsxCall -or $plan.createsFrontFrames){throw 'Slot assembly plan mismatch'}
    Write-Output 'PASS explicit slots, native component identity, one-call assembly and no-frame-rebuild contract'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}
