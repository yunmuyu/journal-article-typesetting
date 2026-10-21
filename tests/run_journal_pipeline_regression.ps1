#Requires -Version 7.0
$ErrorActionPreference='Stop'
$entry=Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-JournalPipeline.ps1'
if(-not(Test-Path -LiteralPath $entry)){throw 'ENTRY_NOT_IMPLEMENTED'}
$root=Join-Path (Split-Path -Parent $PSScriptRoot) ('.local/work/pipeline-regression-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
function WriteJson($path,$value){[IO.File]::WriteAllText($path,($value|ConvertTo-Json -Depth 25),[Text.UTF8Encoding]::new($false))}
function Assert($value,$code){if(-not $value){throw $code}}
$worker=Join-Path $root 'worker.ps1'
@'
param($InputPath,$OutputPath,$CounterPath)
$ErrorActionPreference='Stop'
[IO.File]::WriteAllText($OutputPath,([IO.File]::ReadAllText($InputPath)+'-processed'))
[IO.File]::AppendAllText($CounterPath,"run`n")
'@ | Set-Content -LiteralPath $worker -Encoding utf8BOM
$source=Join-Path $root 'source.txt';$first=Join-Path $root 'first.txt';$last=Join-Path $root 'last.txt'
$c1=Join-Path $root 'first-runs.txt';$c2=Join-Path $root 'second-runs.txt'
[IO.File]::WriteAllText($source,'original')
$specPath=Join-Path $root 'pipeline.json';$statePath=Join-Path $root 'state.json'
$exe=(Get-Command pwsh).Source
$spec=@{schemaVersion=1;statePath=$statePath;workingDirectory=$root;stages=@(
 @{id='first';executable=$exe;arguments=@('-NoProfile','-File',$worker,$source,$first,$c1);inputFiles=@($source,$worker);dependsOn=@();outputs=@($first)},
 @{id='second';executable=$exe;arguments=@('-NoProfile','-File',$worker,$first,$last,$c2);inputFiles=@($worker);dependsOn=@('first');outputs=@($last)}
)}
WriteJson $specPath $spec
& $exe -NoProfile -File $entry -SpecPath $specPath
Assert ($LASTEXITCODE -eq 0) 'FIRST_RUN_FAILED'
& $exe -NoProfile -File $entry -SpecPath $specPath
Assert ($LASTEXITCODE -eq 0) 'UNCHANGED_RERUN_FAILED'
Assert (@(Get-Content -LiteralPath $c1).Count -eq 1) 'REEXECUTED_UNCHANGED_FIRST'
Assert (@(Get-Content -LiteralPath $c2).Count -eq 1) 'REEXECUTED_UNCHANGED_DEPENDENT'
[IO.File]::WriteAllText($source,'changed')
& $exe -NoProfile -File $entry -SpecPath $specPath
Assert ($LASTEXITCODE -eq 0) 'CHANGED_INPUT_RERUN_FAILED'
Assert (@(Get-Content -LiteralPath $c1).Count -eq 2) 'STATIC_INPUT_NOT_INVALIDATED'
Assert (@(Get-Content -LiteralPath $c2).Count -eq 2) 'DEPENDENT_NOT_INVALIDATED'
Assert ([IO.File]::ReadAllText($last) -eq 'changed-processed-processed') 'WRONG_FINAL_RESULT'
[IO.File]::WriteAllText($last,'external-edit')
& $exe -NoProfile -File $entry -SpecPath $specPath
Assert ($LASTEXITCODE -ne 0) 'EXTERNAL_EDIT_OVERWRITTEN'
Assert ([IO.File]::ReadAllText($last) -eq 'external-edit') 'EXTERNAL_EDIT_NOT_PRESERVED'
$badWorker=Join-Path $root 'bad.ps1';$badOutput=Join-Path $root 'bad.json'
'param($OutputPath); [IO.File]::WriteAllText($OutputPath,''{"passed":false}'')'|Set-Content -LiteralPath $badWorker -Encoding utf8BOM
$badSpec=@{schemaVersion=1;statePath=(Join-Path $root 'bad-state.json');workingDirectory=$root;stages=@(@{id='check';executable=$exe;arguments=@('-NoProfile','-File',$badWorker,$badOutput);inputFiles=@($badWorker);dependsOn=@();outputs=@($badOutput);assertions=@(@{path=$badOutput;property='passed';expected=$true})})}
WriteJson (Join-Path $root 'bad-pipeline.json') $badSpec
& $exe -NoProfile -File $entry -SpecPath (Join-Path $root 'bad-pipeline.json')
Assert ($LASTEXITCODE -ne 0) 'EXIT_ZERO_FALSE_CHECK_ACCEPTED'
$badState=Get-Content -LiteralPath $badSpec.statePath -Raw|ConvertFrom-Json
Assert ($badState.stages.check.status -eq 'failed') 'FAILED_CHECKPOINT_NOT_SAVED'
'param($OutputPath); [IO.File]::WriteAllText($OutputPath,''{"passed":true}'')'|Set-Content -LiteralPath $badWorker -Encoding utf8BOM
& $exe -NoProfile -File $entry -SpecPath (Join-Path $root 'bad-pipeline.json')
Assert ($LASTEXITCODE -eq 0) 'FIXED_CHECK_DID_NOT_RESUME'
$unknown=Join-Path $root 'unrelated.json';[IO.File]::WriteAllText($unknown,'{"keep":"unchanged"}')
$before=[IO.File]::ReadAllText($unknown);$badSpec.statePath=$unknown;WriteJson (Join-Path $root 'foreign-spec.json') $badSpec
& $exe -NoProfile -File $entry -SpecPath (Join-Path $root 'foreign-spec.json')
Assert ($LASTEXITCODE -ne 0) 'FOREIGN_STATE_ACCEPTED'
Assert ([IO.File]::ReadAllText($unknown) -ceq $before) 'FOREIGN_STATE_OVERWRITTEN'
Write-Output "PASS pipeline: unchanged reuse, changed-input propagation, external-edit protection, false-result failure. Evidence: $root"
