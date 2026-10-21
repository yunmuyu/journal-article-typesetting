$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('journal-batch-regression-'+[guid]::NewGuid().ToString('N'))
$tools=Join-Path $PSScriptRoot '..\2-导入_InDesign'
function WriteJson([object]$Value,[string]$Path){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))}
function MakeImage([string]$Path,[bool]$HugeWhitespace){
    Add-Type -AssemblyName System.Drawing
    $bitmap=[Drawing.Bitmap]::new(600,400);$graphics=[Drawing.Graphics]::FromImage($bitmap)
    try{$graphics.Clear([Drawing.Color]::White);$rect=if($HugeWhitespace){[Drawing.Rectangle]::new(260,160,80,80)}else{[Drawing.Rectangle]::new(20,20,560,360)};$graphics.FillRectangle([Drawing.Brushes]::Black,$rect);$bitmap.Save($Path,[Drawing.Imaging.ImageFormat]::Png)}finally{$graphics.Dispose();$bitmap.Dispose()}
}
try{
    $figures=Join-Path $root 'figures';$output=Join-Path $root 'output';$queue=Join-Path $root 'queue';foreach($dir in @($root,$figures,$output)){[void](New-Item -ItemType Directory -Path $dir -Force)}
    $source=Join-Path $root 'source.docx';[IO.File]::WriteAllText($source,'fixture')
    $article=Join-Path $root 'article.json';WriteJson ([ordered]@{blocks=@([ordered]@{role='body';text='正文说明如图1所示。'},[ordered]@{role='figure_caption';text='图1  测试图'},[ordered]@{role='body';text=('正文'*800)})}) $article
    $image=Join-Path $figures '测试者-图1.png';MakeImage $image $false
    $task=Join-Path $root 'task.json';WriteJson ([ordered]@{taskId='fixture-ready';author='测试者';sourceWord=$source;articleJson=$article;figureDirectory=$figures;outputDirectory=$output;expectedPages=2}) $task
    $result=& (Join-Path $tools 'New-JournalLayoutPlan.ps1') -TaskPath $task -OutputPath (Join-Path $output 'ready.json')|ConvertFrom-Json
    if($LASTEXITCODE -notin @($null,0) -or $result.status -ne 'ready' -or $result.layout.figures[0].anchorAfterBlock -ne 0){throw "Ready plan regression failed: exit=$LASTEXITCODE status=$($result.status) anchor=$($result.layout.figures[0].anchorAfterBlock)"}
    Remove-Item -LiteralPath $image; $missing=& (Join-Path $tools 'New-JournalLayoutPlan.ps1') -TaskPath $task -OutputPath (Join-Path $output 'missing.json')|ConvertFrom-Json
    if($LASTEXITCODE -ne 2 -or $missing.status -ne 'needs_input' -or @($missing.issues.code) -notcontains 'FIGURE_MISSING'){throw 'Missing figure was not blocked'}
    $badName=Join-Path $figures '图1-source.png';MakeImage $badName $false;$named=& (Join-Path $tools 'New-JournalLayoutPlan.ps1') -TaskPath $task -OutputPath (Join-Path $output 'name.json')|ConvertFrom-Json
    if($LASTEXITCODE -ne 2 -or @($named.issues.code) -notcontains 'FIGURE_NAME'){throw 'Unexpected figure name was not blocked'}
    MakeImage (Join-Path $figures '图1-other.png') $false;$ambiguous=& (Join-Path $tools 'New-JournalLayoutPlan.ps1') -TaskPath $task -OutputPath (Join-Path $output 'ambiguous.json')|ConvertFrom-Json
    if($LASTEXITCODE -ne 2 -or @($ambiguous.issues.code) -notcontains 'FIGURE_AMBIGUOUS'){throw 'Ambiguous figure candidates were not blocked'}
    Remove-Item -LiteralPath (Join-Path $figures '图1-source.png'),(Join-Path $figures '图1-other.png')
    MakeImage $image $true;$white=& (Join-Path $tools 'New-JournalLayoutPlan.ps1') -TaskPath $task -OutputPath (Join-Path $output 'white.json')|ConvertFrom-Json
    if($LASTEXITCODE -ne 2 -or @($white.issues.code) -notcontains 'FIGURE_WHITESPACE'){throw 'Large whitespace was not blocked'}
    $reviewTask=Get-Content -LiteralPath $task -Raw|ConvertFrom-Json
    $reviewTask|Add-Member -NotePropertyName figureWhitespaceReviews -NotePropertyValue @(@{name=[IO.Path]::GetFileName($image);sha256=(Get-FileHash -LiteralPath $image -Algorithm SHA256).Hash;reason='Verified intentional whitespace inside the source screenshot'})
    WriteJson $reviewTask $task
    $reviewed=& (Join-Path $tools 'New-JournalLayoutPlan.ps1') -TaskPath $task -OutputPath (Join-Path $output 'reviewed-white.json')|ConvertFrom-Json
    if($reviewed.status -ne 'ready' -or @($reviewed.warnings.code) -notcontains 'FIGURE_WHITESPACE_REVIEWED'){throw 'Hash-bound whitespace review was not recorded'}
    $reviewTask.figureWhitespaceReviews[0].sha256=('0'*64);WriteJson $reviewTask $task
    $staleWhite=& (Join-Path $tools 'New-JournalLayoutPlan.ps1') -TaskPath $task -OutputPath (Join-Path $output 'stale-white.json')|ConvertFrom-Json
    if(@($staleWhite.issues.code) -notcontains 'FIGURE_WHITESPACE'){throw 'Stale whitespace review bypassed the check'}
    MakeImage $image $false;& (Join-Path $tools 'Invoke-JournalBatch.ps1') -Action Register -QueueDirectory $queue -TaskPath $task|Out-Null
    & (Join-Path $tools 'Invoke-JournalBatch.ps1') -Action Preflight -QueueDirectory $queue -TaskId 'fixture-ready'|Out-Null
    # Given: a successful stage has a versioned checkpoint containing every reusable input.
    $template=Join-Path $root 'template-v4-QA.indd';[IO.File]::WriteAllText($template,'template-v4')
    $rules=Join-Path $root 'rules-v7.json';[IO.File]::WriteAllText($rules,'{}')
    $config=Join-Path $root 'config-v3.json';[IO.File]::WriteAllText($config,'{}')
    $checkpointData=Join-Path $root 'checkpoint-data.json'
    WriteJson ([ordered]@{
        schemaVersion=1;taskId='fixture-ready';currentTemplate=[ordered]@{version='v4';status='passed'}
        currentArticle='测试者';stage='formulas-approved'
        inputs=@(
            [ordered]@{name='sourceWord';path=$source;sha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash}
            [ordered]@{name='template';path=$template;sha256=(Get-FileHash -LiteralPath $template -Algorithm SHA256).Hash}
            [ordered]@{name='rules';path=$rules;sha256=(Get-FileHash -LiteralPath $rules -Algorithm SHA256).Hash}
            [ordered]@{name='config';path=$config;sha256=(Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash}
        )
        outputPath=(Join-Path $output 'fixture-QA.indd');rulesVersion='rules-v7';configVersion='config-v3'
        failure=[ordered]@{classification=$null;reason=$null};nextAction='run-assembly-v3';forbiddenReuse=@('legacy-template','failed-layout')
    }) $checkpointData
    # When: the checkpoint is attached and then resumed.
    $saved=& (Join-Path $tools 'Invoke-JournalBatch.ps1') -Action Checkpoint -QueueDirectory $queue -TaskId 'fixture-ready' -CheckpointDataPath $checkpointData|ConvertFrom-Json
    $resumed=& (Join-Path $tools 'Invoke-JournalBatch.ps1') -Action Resume -QueueDirectory $queue -TaskId 'fixture-ready'|ConvertFrom-Json
    # Then: queue and checkpoint agree on the exact state and the next action is recoverable.
    $checkpointRecord=Get-Content -LiteralPath (Join-Path $queue 'tasks\fixture-ready.json') -Raw|ConvertFrom-Json
    if($saved.schemaVersion -ne 1 -or $saved.nextAction -ne 'run-assembly-v3'){throw 'Checkpoint did not preserve the versioned next action'}
    if(-not $checkpointRecord.checkpointPath -or -not $checkpointRecord.checkpointSha256){throw 'Queue task did not attach checkpoint identity'}
    if($resumed.verified -ne $true -or $resumed.nextAction -ne 'run-assembly-v3' -or $resumed.stage -ne 'formulas-approved'){throw 'Resume did not return the verified continuation'}
    if(@($resumed.forbiddenReuse) -notcontains 'failed-layout'){throw 'Resume lost forbidden-reuse state'}
    # Given: the task manifest itself has not changed; re-registration must not discard valid progress.
    & (Join-Path $tools 'Invoke-JournalBatch.ps1') -Action Register -QueueDirectory $queue -TaskPath $task|Out-Null
    $registeredAgain=Get-Content -LiteralPath (Join-Path $queue 'tasks\fixture-ready.json') -Raw|ConvertFrom-Json
    if($registeredAgain.checkpointSha256 -ne $checkpointRecord.checkpointSha256){throw 'Unchanged registration discarded the attached checkpoint'}
    # Given: a checkpointed input changes after the successful stage.
    [IO.File]::AppendAllText($config,'changed')
    # When: context restoration tries to resume, then it must stop before reusing stale work.
    $staleBlocked=$false;try{& (Join-Path $tools 'Invoke-JournalBatch.ps1') -Action Resume -QueueDirectory $queue -TaskId 'fixture-ready'|Out-Null}catch{$staleBlocked=$_.Exception.Message -match 'CHECKPOINT_INPUT_CHANGED'}
    if(-not $staleBlocked){throw 'Resume accepted a changed checkpoint input'}
    $lease=& (Join-Path $tools 'Invoke-JournalBatch.ps1') -Action Acquire -QueueDirectory $queue -TaskId 'fixture-ready' -Lane InDesign|ConvertFrom-Json
    $blocked=$false;try{& (Join-Path $tools 'Invoke-JournalBatch.ps1') -Action Acquire -QueueDirectory $queue -Lane InDesign|Out-Null}catch{$blocked=$true};if(-not $blocked){throw 'Single-writer lane accepted a second lease'}
    & (Join-Path $tools 'Invoke-JournalBatch.ps1') -Action Release -QueueDirectory $queue -Lane InDesign -LeaseId $lease.leaseId|Out-Null
    $lease=& (Join-Path $tools 'Invoke-JournalBatch.ps1') -Action Acquire -QueueDirectory $queue -TaskId 'fixture-ready' -Lane InDesign|ConvertFrom-Json
    & (Join-Path $tools 'Invoke-JournalBatch.ps1') -Action Complete -QueueDirectory $queue -Lane InDesign -LeaseId $lease.leaseId|Out-Null
    $evidence=Join-Path $root 'review.txt';[IO.File]::WriteAllText($evidence,'reviewed')
    $passed=& (Join-Path $tools 'Invoke-JournalBatch.ps1') -Action Pass -QueueDirectory $queue -TaskId 'fixture-ready' -EvidencePath $evidence|ConvertFrom-Json
    if($passed.status -ne 'passed'){throw 'Queue did not reach passed'}
    # Given: the manifest changes, any checkpoint based on its former inputs is invalidated.
    $taskObject=Get-Content -LiteralPath $task -Raw|ConvertFrom-Json;$taskObject.expectedPages=3;WriteJson $taskObject $task
    & (Join-Path $tools 'Invoke-JournalBatch.ps1') -Action Register -QueueDirectory $queue -TaskPath $task|Out-Null
    $invalidated=Get-Content -LiteralPath (Join-Path $queue 'tasks\fixture-ready.json') -Raw|ConvertFrom-Json
    if($invalidated.checkpointPath -or $invalidated.checkpointSha256){throw 'Changed manifest retained a stale checkpoint attachment'}
    'PASS external preflight, versioned checkpoint resume, recoverable state and single-writer queue'
}finally{if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}}
