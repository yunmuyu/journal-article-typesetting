$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('journal-asset-pipeline-' + [guid]::NewGuid().ToString('N'))
$tools = Join-Path $PSScriptRoot '..\2-导入_InDesign'

function WriteJson([object]$Value, [string]$Path) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
}

function MakeImage([string]$Path, [int]$Inset) {
    Add-Type -AssemblyName System.Drawing
    $bitmap = [Drawing.Bitmap]::new(600, 400)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([Drawing.Color]::White)
        $graphics.FillRectangle([Drawing.Brushes]::Black, [Drawing.Rectangle]::new($Inset, $Inset, 600 - 2 * $Inset, 400 - 2 * $Inset))
        $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

try {
    # Given: one figure-only article with a stable content-addressed cache directory.
    $figures = Join-Path $root 'figures'
    $output = Join-Path $root 'output'
    $cache = Join-Path $root 'cache'
    $queue = Join-Path $root 'queue'
    foreach ($directory in @($root, $figures, $output, $cache)) { [void](New-Item -ItemType Directory -Path $directory -Force) }
    $source = Join-Path $root 'source.docx'
    [IO.File]::WriteAllText($source, 'fixture')
    $article = Join-Path $root 'article.json'
    WriteJson ([ordered]@{ blocks = @(
        [ordered]@{ role = 'body'; text = '正文说明如图1所示。' },
        [ordered]@{ role = 'figure_caption'; text = '图1  测试图' }
    ) }) $article
    $image = Join-Path $figures '测试者-图1.png'
    MakeImage $image 20
    $task = Join-Path $root 'task.json'
    WriteJson ([ordered]@{
        taskId = 'asset-fixture'; author = '测试者'; sourceWord = $source; articleJson = $article
        figureDirectory = $figures; outputDirectory = $output; assetCacheDirectory = $cache
    }) $task

    # When: preflight runs twice without changing the source image.
    $first = & (Join-Path $tools 'New-JournalLayoutPlan.ps1') -TaskPath $task -OutputPath (Join-Path $output 'first.json') | ConvertFrom-Json
    $second = & (Join-Path $tools 'New-JournalLayoutPlan.ps1') -TaskPath $task -OutputPath (Join-Path $output 'second.json') | ConvertFrom-Json

    # Then: the first run creates complete metadata and the second is a SHA256 cache hit.
    if ($first.pipeline -ne 'fast-graphics') { throw "Expected fast-graphics, got $($first.pipeline)" }
    if ($first.layout.widePanelBoundaries.Count -ne 1 -or $first.layout.widePanelBoundaries[0].paragraphText -ne '正文说明如图1所示。' -or -not $first.layout.widePanelBoundaries[0].panelBreakAfterParagraph) { throw 'Double-column figure did not receive a panel break after its complete preceding paragraph' }
    if ($first.layout.widePanelBoundaries[0].PSObject.Properties['keepAllLinesTogether']) { throw 'Wide-panel planning incorrectly forces a long paragraph into one frame' }
    if ($first.assets[0].cache.status -ne 'miss' -or $second.assets[0].cache.status -ne 'hit') { throw 'Asset cache did not miss then hit' }
    foreach ($field in @('sha256', 'widthMm', 'heightMm', 'pageBoxes', 'fonts', 'contentType', 'recommendedScalePercent', 'raster')) {
        if (-not $second.assets[0].PSObject.Properties[$field]) { throw "Cached metadata is missing $field" }
    }
    if (-not (Test-Path -LiteralPath $second.assets[0].cache.recordPath)) { throw 'Cache record was not persisted' }

    # When: the image content changes at the same path.
    MakeImage $image 30
    $changed = & (Join-Path $tools 'New-JournalLayoutPlan.ps1') -TaskPath $task -OutputPath (Join-Path $output 'changed.json') | ConvertFrom-Json

    # Then: a new SHA key is inspected and persisted rather than reusing stale metadata.
    if ($changed.assets[0].cache.status -ne 'miss' -or $changed.assets[0].sha256 -eq $second.assets[0].sha256) { throw 'Changed figure did not invalidate the SHA cache' }
    if ($changed.exceptionSummary.needsInput -or $changed.exceptionSummary.count -ne 0) { throw 'Clean preflight produced an exception summary' }

    # Given: one wide panel has no unique preceding reference paragraph.
    WriteJson ([ordered]@{ blocks = @(
        [ordered]@{ role = 'body'; text = '正文没有明确的前置引用。' },
        [ordered]@{ role = 'figure_caption'; text = '图1  测试图' }
    ) }) $article
    $noBoundary = & (Join-Path $tools 'New-JournalLayoutPlan.ps1') -TaskPath $task -OutputPath (Join-Path $output 'no-boundary.json') | ConvertFrom-Json

    # Then: the consolidated exception list blocks Adobe work before layout begins.
    if ($LASTEXITCODE -ne 2 -or -not $noBoundary.exceptionSummary.needsInput -or @($noBoundary.exceptionSummary.codes) -notcontains 'WIDE_PANEL_ANCHOR') { throw 'Missing wide-panel boundary was not concentrated into needs_input' }

    # Given: a six-column table is planned as a wide panel.
    $tableJson = Join-Path $root 'tables.json'
    WriteJson ([ordered]@{ tables = @([ordered]@{ rows = @(@('A','B','C','D','E','F'), @('1','2','3','4','5','6')) }) }) $tableJson
    $tableTask = Get-Content -LiteralPath $task -Raw | ConvertFrom-Json
    $tableTask | Add-Member -NotePropertyName tableJson -NotePropertyValue $tableJson
    WriteJson $tableTask $task
    WriteJson ([ordered]@{ blocks = @(
        [ordered]@{ role = 'body'; text = '参数结果见表1。' },
        [ordered]@{ role = 'table_caption'; text = '表1  参数结果' }
    ) }) $article
    $tablePlan = & (Join-Path $tools 'New-JournalLayoutPlan.ps1') -TaskPath $task -OutputPath (Join-Path $output 'wide-table.json') | ConvertFrom-Json

    # Then: the same paragraph-boundary contract is produced for the table.
    $tableBoundary = @($tablePlan.layout.widePanelBoundaries | Where-Object { $_.kind -eq 'table' -and $_.number -eq 1 })
    if ($tableBoundary.Count -ne 1 -or $tableBoundary[0].paragraphText -ne '参数结果见表1。' -or -not $tableBoundary[0].panelBreakAfterParagraph) { throw 'Double-column table did not receive one paragraph boundary' }

    # Given: formula counts select the standard and formula-dense routes.
    $formulaManifest = Join-Path $root 'formulas.json'
    $tableTask.PSObject.Properties.Remove('tableJson')
    WriteJson $tableTask $task
    $formulaTask = Get-Content -LiteralPath $task -Raw | ConvertFrom-Json
    $formulaTask | Add-Member -NotePropertyName formulaManifest -NotePropertyValue $formulaManifest
    WriteJson ([ordered]@{ blocks = @([ordered]@{ role = 'body'; text = '正文⟦EQ-1⟧。' }) }) $article
    WriteJson ([ordered]@{ formula_count = 1 }) $formulaManifest
    WriteJson $formulaTask $task
    $standard = & (Join-Path $tools 'New-JournalLayoutPlan.ps1') -TaskPath $task -OutputPath (Join-Path $output 'standard.json') | ConvertFrom-Json
    if ($standard.pipeline -ne 'standard') { throw "Expected standard pipeline, got $($standard.pipeline)" }
    $markers = 1..10 | ForEach-Object { "⟦EQ-$_⟧" }
    WriteJson ([ordered]@{ blocks = @([ordered]@{ role = 'body'; text = ($markers -join '') }) }) $article
    WriteJson ([ordered]@{ formula_count = 10 }) $formulaManifest
    $dense = & (Join-Path $tools 'New-JournalLayoutPlan.ps1') -TaskPath $task -OutputPath (Join-Path $output 'dense.json') | ConvertFrom-Json
    if ($dense.pipeline -ne 'formula-dense') { throw "Expected formula-dense pipeline, got $($dense.pipeline)" }

    # Restore the clean graphics task for queue-state verification.
    WriteJson ([ordered]@{ blocks = @(
        [ordered]@{ role = 'body'; text = '正文说明如图1所示。' },
        [ordered]@{ role = 'figure_caption'; text = '图1  测试图' }
    ) }) $article
    $formulaTask.PSObject.Properties.Remove('formulaManifest')
    WriteJson $formulaTask $task

    # Given: the task is registered and preflighted.
    & (Join-Path $tools 'Invoke-JournalBatch.ps1') -Action Register -QueueDirectory $queue -TaskPath $task | Out-Null
    & (Join-Path $tools 'Invoke-JournalBatch.ps1') -Action Preflight -QueueDirectory $queue -TaskId 'asset-fixture' | Out-Null
    $record = Get-Content -LiteralPath (Join-Path $queue 'tasks\asset-fixture.json') -Raw | ConvertFrom-Json

    # Then: the durable stage and measured preflight duration are available without translating legacy status.
    if ($record.workflowStage -ne 'formulas-approved' -or $record.stageLabel -ne '公式通过') { throw "Unexpected durable stage: $($record.workflowStage)" }
    if ($record.timings.preflightMs -lt 0) { throw 'Preflight duration was not recorded' }

    # When: assembly and review milestones are completed through the recoverable queue.
    $lease = & (Join-Path $tools 'Invoke-JournalBatch.ps1') -Action Acquire -QueueDirectory $queue -TaskId 'asset-fixture' -Lane InDesign | ConvertFrom-Json
    & (Join-Path $tools 'Invoke-JournalBatch.ps1') -Action Complete -QueueDirectory $queue -Lane InDesign -LeaseId $lease.leaseId | Out-Null
    $evidence = Join-Path $root 'evidence.txt'
    [IO.File]::WriteAllText($evidence, 'verified')
    foreach ($stage in @('key-pages-approved', 'full-article-approved', 'merged')) {
        & (Join-Path $tools 'Invoke-JournalBatch.ps1') -Action Advance -QueueDirectory $queue -TaskId 'asset-fixture' -Stage $stage -EvidencePath $evidence -ElapsedMs 7 | Out-Null
    }
    & (Join-Path $tools 'Invoke-JournalBatch.ps1') -Action RecordTiming -QueueDirectory $queue -TaskId 'asset-fixture' -TimingStage WordExtraction -ElapsedMs 11 | Out-Null
    $done = Get-Content -LiteralPath (Join-Path $queue 'tasks\asset-fixture.json') -Raw | ConvertFrom-Json

    # Then: all user-facing stages and per-phase timings survive in one task record.
    if ($done.workflowStage -ne 'merged' -or $done.stageLabel -ne '已合入') { throw 'Queue did not reach merged' }
    if ($done.timings.wordExtractionMs -ne 11 -or $done.timings.keyPreviewMs -ne 7 -or $done.timings.fullExportMs -ne 7 -or $done.timings.mergeMs -ne 7) { throw 'Stage timings were not retained' }
    if ($done.timings.indesignAssemblyMs -lt 0 -or $done.timings.indesignAssemblyMs -gt 60000) { throw ('Assembly timing contains timezone skew: '+$done.timings.indesignAssemblyMs) }
    $requiredStages = @('extracted', 'figures-approved', 'formulas-approved', 'initial-layout-complete', 'key-pages-approved', 'full-article-approved', 'merged')
    foreach ($stage in $requiredStages) { if (@($done.history.workflowStage) -notcontains $stage) { throw "History is missing $stage" } }

    'PASS SHA256 figure cache, pipeline routing, exception summary, durable stages and timing records'
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
