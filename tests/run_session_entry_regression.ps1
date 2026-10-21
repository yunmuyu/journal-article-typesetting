param()

$ErrorActionPreference = 'Stop'
$entry = Join-Path (Split-Path $PSScriptRoot) '2-导入_InDesign\Invoke-JournalLayout.ps1'
$source = [IO.File]::ReadAllText($entry, [Text.Encoding]::UTF8)
$slotEntry = Join-Path (Split-Path $PSScriptRoot) '2-导入_InDesign\Invoke-JournalSlotAssembly.ps1'
$slotSource = [IO.File]::ReadAllText($slotEntry, [Text.Encoding]::UTF8)
$negativeEntry = Join-Path $PSScriptRoot 'run_journal_layout_negative_regression.ps1'
$negativeSource = [IO.File]::ReadAllText($negativeEntry, [Text.Encoding]::UTF8)
[void][scriptblock]::Create($source)
[void][scriptblock]::Create($slotSource)

$checks = [ordered]@{
    'reuses an already open document by full path' = $source.Contains('String(candidate.fullName.fsName).toLowerCase()===targetPath')
    'opens only when no matching document is open' = $source.Contains('if(!d){d=app.open(target);opened=true;}')
    'supports key-page preview export' = $source.Contains("if(previewScope==='Full')") -and $source.Contains('cfg.previewPageIndices')
    'does not export IDML unless requested' = $source.Contains('if($exportIdmlJs)d.exportFile')
    'switch parameters are not overwritten by JavaScript literals' = -not $source.Contains("`$exportIdml=if(") -and -not $source.Contains("`$closeWhenDone=if(")
    'blocks a visible script alert before COM work' = $source.Contains("MainWindowTitle -match '^(Script Alert|")
    'rejects unversioned check configurations before COM' = $source.Contains("if(-not `$config.configVersion)") -and $source.Contains("if(-not `$config.templateContractVersion)")
    'rejects template contract mismatch before mutation' = $source.Contains("TEMPLATE_CONTRACT_MISMATCH")
    'slot assembly does not retarget activeDocument' = -not $slotSource.Contains('app.activeDocument=d')
    'slot assembly closes only documents opened by the entry' = $slotSource.Contains('if($close&&opened)closeExact(d,SaveOptions.YES)')
    'slot assembly close validates path and document id' = $slotSource.Contains('function closeExact') -and $slotSource.Contains('TARGET_PATH_CHANGED') -and $slotSource.Contains('TARGET_ID_CHANGED')
    'negative regression never uses activeDocument as the close target' = -not $negativeSource.Contains('activeDocument') -and $negativeSource.Contains('closeExact')
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value })
if ($failed.Count) {
    throw 'Session entry regression failed: ' + (($failed | ForEach-Object Key) -join '; ')
}

'PASS session reuse, key preview, optional IDML, and modal-dialog guard'
